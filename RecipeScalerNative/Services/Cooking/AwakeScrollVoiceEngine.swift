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
    /// Bumped on every `stop` / new recognition task so cancelled-task
    /// callbacks cannot restart a freshly rebuilt session (same epoch).
    private var recognitionAttempt: UInt64 = 0
    private(set) var audioEngineBuildCount = 0
    private(set) var recognitionTaskCount = 0
    private(set) var isRunning = false
    /// Test seam: sleep this long instead of `restartDelay` after a failed restart.
    var testRestartDelayOverride: TimeInterval?
    /// Test seam: when set, `startSession()` returns this and skips hardware.
    var testStartSessionResult: Bool?
    /// True only while `testStartSessionResult == true` stands in for a live engine,
    /// so `isFinal` can rotate recognition without an `AVAudioEngine`.
    private var testSessionStandIn = false
    var now: () -> Date = { Date() }

    /// Errors that mean "this task was superseded", not "the session is sick".
    nonisolated static func isIgnorableRecognitionError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return true }
        if ns.domain == NSCocoaErrorDomain, ns.code == NSUserCancelledError { return true }
        // SFSpeechRecognitionTask.cancel() typically delivers
        // `kAFAssistantErrorDomain` code 216.
        if ns.domain == "kAFAssistantErrorDomain", ns.code == 216 { return true }
        return false
    }

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
            isRunning = false
            testSessionStandIn = false
        } else {
            isRunning = true
        }
        return started
    }

    func stop() {
        recognitionAttempt += 1
        runtime.tearDown()
        onAction = nil
        isRunning = false
        testSessionStandIn = false
        lastEmittedAction = nil
        lastFireTokenCount = 0
        fireGate.reset()
    }

    private func startSession() -> Bool {
        if let forced = testStartSessionResult {
            testSessionStandIn = forced
            if forced {
                recognitionTaskCount += 1
            }
            return forced
        }
        testSessionStandIn = false
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
        audioEngineBuildCount += 1
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
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak runtime] buffer, _ in
            runtime?.request?.append(buffer)
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

        beginRecognitionTask(recognizer: recognizer, request: request, epoch: epoch)
        scheduleRearm(epoch: epoch)
        return true
    }

    private func beginRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        epoch: UInt64
    ) {
        recognitionAttempt += 1
        recognitionTaskCount += 1
        let attempt = recognitionAttempt
        runtime.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self,
                      self.epoch == epoch,
                      self.recognitionAttempt == attempt else { return }
                if let result {
                    self.considerTranscript(
                        result.bestTranscription.formattedString,
                        isFinal: result.isFinal,
                        epoch: epoch
                    )
                    if result.isFinal {
                        self.rotateRecognitionIfCurrent(epoch: epoch)
                    }
                }
                if let error {
                    guard !Self.isIgnorableRecognitionError(error) else { return }
                    self.scheduleRestartIfCurrent(epoch: epoch, error: error)
                }
            }
        }
    }

    private func scheduleRearm(epoch: UInt64) {
        runtime.rearmTask?.cancel()
        runtime.rearmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 55_000_000_000)
            guard !Task.isCancelled else { return }
            self?.restartDelay = 1.0
            self?.rotateRecognitionIfCurrent(epoch: epoch)
        }
    }

    /// Planned 55s re-arm: rotate the Speech request/task only. Keep
    /// `SFSpeechRecognizer`, `AVAudioEngine`, tap, and audio session.
    func rotateRecognitionForTesting() {
        rotateRecognitionIfCurrent(epoch: epoch)
    }

    /// Test seam: a final recognition result, without a live `SFSpeechRecognitionTask`.
    func deliverRecognitionResultForTesting(transcript: String, isFinal: Bool) {
        considerTranscript(transcript, isFinal: isFinal, epoch: epoch)
        if isFinal {
            rotateRecognitionIfCurrent(epoch: epoch)
        }
    }

    /// Test seam: the error-restart path, using the current epoch and callback.
    func failRestartForTesting() {
        restartIfCurrent(epoch: epoch)
    }

    private func rotateRecognitionIfCurrent(epoch: UInt64) {
        guard self.epoch == epoch, onAction != nil else { return }
        if testSessionStandIn {
            recognitionAttempt += 1
            recognitionTaskCount += 1
            scheduleRearm(epoch: epoch)
            return
        }
        guard runtime.audioEngine?.isRunning == true,
              let recognizer = runtime.recognizer
        else {
            restartIfCurrent(epoch: epoch)
            return
        }
        recognitionAttempt += 1
        runtime.task?.cancel()
        runtime.request?.endAudio()
        runtime.task = nil
        runtime.request = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        runtime.request = request
        beginRecognitionTask(recognizer: recognizer, request: request, epoch: epoch)
        scheduleRearm(epoch: epoch)
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
        AppLog.debug(
            .gesture,
            "awake_scroll_voice_fired",
            data: ["chip": AwakeScrollVoiceClassifier.chip(from: normalized)?.rawValue ?? ""]
        )
        onAction?(action, epoch, normalized)
    }

    private func scheduleRestartIfCurrent(epoch: UInt64, error: Error) {
        guard self.epoch == epoch, onAction != nil else { return }
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        AppLog.debug(
            .gesture,
            "awake_scroll_speech_restart",
            data: [
                "delayMs": String(Int(delay * 1000)),
                "errorDomain": (error as NSError).domain,
                "errorCode": String((error as NSError).code),
            ]
        )
        runtime.restartBackoffTask?.cancel()
        runtime.restartBackoffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.restartIfCurrent(epoch: epoch)
        }
    }

    private func restartIfCurrent(epoch: UInt64) {
        guard self.epoch == epoch, let callback = onAction else { return }
        let capturedLocale = locale
        runtime.tearDown()
        let started = start(epoch: epoch, locale: capturedLocale, onAction: callback)
        if !started {
            scheduleFailedRestart(epoch: epoch, locale: capturedLocale, callback: callback)
        }
    }

    /// `start` nils `onAction` when it fails, so the retry keeps the callback
    /// captured here instead of reading `onAction` again.
    private func scheduleFailedRestart(
        epoch: UInt64,
        locale: Locale,
        callback: @escaping (AwakeScrollAction, UInt64, String) -> Void
    ) {
        restartDelay = min(restartDelay * 2, 30)
        let delay = testRestartDelayOverride ?? restartDelay
        AppLog.debug(
            .gesture,
            "awake_scroll_speech_restart_failed",
            data: ["delayMs": String(Int(delay * 1000))]
        )
        runtime.restartBackoffTask?.cancel()
        runtime.restartBackoffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self, self.epoch == epoch else { return }
            let started = self.start(epoch: epoch, locale: locale, onAction: callback)
            if !started {
                self.scheduleFailedRestart(epoch: epoch, locale: locale, callback: callback)
            }
        }
    }
}
