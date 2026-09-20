import AVFoundation
import Foundation
import Speech

/// Non-MainActor owner so `deinit` can tear down audio/speech without hopping
/// back onto a freed `@MainActor` engine (see `TimerManager` deinit note).
final class AwakeScrollVoiceRuntime {
    var audioEngine: AVAudioEngine?
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var recognizer: SFSpeechRecognizer?
    var rearmTask: Task<Void, Never>?
    var restartBackoffTask: Task<Void, Never>?
    var didActivateAudioSession = false

    deinit {
        tearDown()
    }

    func tearDown() {
        rearmTask?.cancel()
        rearmTask = nil
        restartBackoffTask?.cancel()
        restartBackoffTask = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognizer = nil
        if didActivateAudioSession {
            didActivateAudioSession = false
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }
}

@MainActor
final class AwakeScrollVoiceEngine {
    nonisolated static func recognizerLocale(for language: AppLanguagePreference) -> Locale {
        switch language {
        case .en: Locale(identifier: "en_US")
        case .ru: Locale(identifier: "ru_RU")
        }
    }

    private let runtime = AwakeScrollVoiceRuntime()
    /// Exponential backoff for error-triggered restarts so an unavailable
    /// recognizer (e.g. missing on-device model) cannot hot-loop restarts.
    private var restartDelay: TimeInterval = 1.0
    private var epoch: UInt64 = 0
    private var locale = Locale(identifier: "ru_RU")
    private var onAction: ((AwakeScrollAction, UInt64, String) -> Void)?
    private var lastEmittedAction: AwakeScrollAction?
    private var lastFireTokenCount = 0
    private var fireGate = AwakeScrollVoiceFireGate()
    var now: () -> Date = { Date() }

    func start(
        epoch: UInt64,
        locale: Locale = AwakeScrollVoiceEngine.recognizerLocale(for: AppLanguagePreference.current),
        onAction: @escaping (AwakeScrollAction, UInt64, String) -> Void
    ) -> Bool {
        // Fresh user-initiated session (new epoch) resets the restart backoff;
        // error-driven restarts reuse the same epoch and keep growing it.
        if epoch != self.epoch {
            restartDelay = 1.0
        }
        stop()
        self.epoch = epoch
        self.locale = locale
        self.onAction = onAction
        let started = startSession()
        if !started {
            runtime.tearDown()
            self.onAction = nil
        }
        return started
    }

    func stop() {
        runtime.tearDown()
        onAction = nil
        lastEmittedAction = nil
        lastFireTokenCount = 0
        fireGate.reset()
    }

    private func startSession() -> Bool {
        let recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "ru_RU"))
            ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            AppLog.debug(.gesture, "awake_scroll_speech_unavailable")
            return false
        }
        guard recognizer.supportsOnDeviceRecognition else {
            AppLog.debug(.gesture, "awake_scroll_speech_on_device_unavailable")
            return false
        }
        runtime.recognizer = recognizer
        AppLog.debug(
            .gesture,
            "awake_scroll_speech_locale",
            data: ["locale": locale.identifier]
        )

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        runtime.audioEngine = audioEngine
        runtime.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            runtime.didActivateAudioSession = true
        } catch {
            AppLog.error(.gesture, "awake_scroll_audio_session", data: ["error": error.localizedDescription])
            return false
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            AppLog.error(.gesture, "awake_scroll_audio_engine", data: ["error": error.localizedDescription])
            return false
        }
        AppLog.info(
            .gesture,
            "awake_scroll_speech_mode",
            data: [
                "onDevice": "1",
                "locale": locale.identifier,
            ]
        )

        let capturedEpoch = epoch
        runtime.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.epoch == capturedEpoch else { return }
                if let result {
                    self.considerTranscript(
                        result.bestTranscription.formattedString,
                        isFinal: result.isFinal,
                        epoch: capturedEpoch
                    )
                }
                if let error {
                    self.scheduleRestartIfCurrent(epoch: capturedEpoch, error: error)
                }
            }
        }

        runtime.rearmTask?.cancel()
        runtime.rearmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 55_000_000_000)
            guard !Task.isCancelled else { return }
            self?.restartDelay = 1.0
            self?.restartIfCurrent(epoch: capturedEpoch)
        }
        return true
    }

    private func considerTranscript(_ transcript: String, isFinal: Bool, epoch: UInt64) {
        let normalized = AwakeScrollVoiceClassifier.normalize(transcript)
        let tokenCount = AwakeScrollVoiceClassifier.tokenCount(normalized)
        if tokenCount != lastFireTokenCount {
            lastEmittedAction = nil
        }
        guard let action = fireGate.action(from: transcript, isFinal: isFinal, now: now()) else {
            if lastEmittedAction != nil, AwakeScrollVoiceClassifier.match(normalized) == nil {
                lastEmittedAction = nil
            }
            return
        }
        guard lastEmittedAction != action else { return }
        lastEmittedAction = action
        lastFireTokenCount = tokenCount
        AppLog.debug(.gesture, "awake_scroll_voice_fired", data: ["phrase": normalized])
        onAction?(action, epoch, normalized)
    }

    private func scheduleRestartIfCurrent(epoch: UInt64, error: Error) {
        guard self.epoch == epoch, onAction != nil else { return }
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        AppLog.debug(
            .gesture,
            "awake_scroll_speech_restart",
            data: ["delayMs": String(Int(delay * 1000)), "error": error.localizedDescription]
        )
        runtime.restartBackoffTask?.cancel()
        runtime.restartBackoffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.restartIfCurrent(epoch: epoch)
        }
    }

    private func restartIfCurrent(epoch: UInt64) {
        guard self.epoch == epoch, onAction != nil else { return }
        let callback = onAction
        let locale = locale
        runtime.tearDown()
        if let callback {
            _ = start(epoch: epoch, locale: locale, onAction: callback)
        }
    }
}
