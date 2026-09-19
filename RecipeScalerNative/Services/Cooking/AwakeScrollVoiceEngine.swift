import AVFoundation
import Foundation
import Speech

@MainActor
final class AwakeScrollVoiceEngine {
    nonisolated static func recognizerLocale(for language: AppLanguagePreference) -> Locale {
        switch language {
        case .en: Locale(identifier: "en_US")
        case .ru: Locale(identifier: "ru_RU")
        }
    }

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var rearmTask: Task<Void, Never>?
    private var epoch: UInt64 = 0
    private var locale = Locale(identifier: "ru_RU")
    private var onAction: ((AwakeScrollAction, UInt64, String) -> Void)?
    private var didActivateAudioSession = false
    private var lastEmittedAction: AwakeScrollAction?

    func start(
        epoch: UInt64,
        locale: Locale = AwakeScrollVoiceEngine.recognizerLocale(for: AppLanguagePreference.current),
        onAction: @escaping (AwakeScrollAction, UInt64, String) -> Void
    ) {
        stop()
        self.epoch = epoch
        self.locale = locale
        self.onAction = onAction
        startSession()
    }

    func stop() {
        rearmTask?.cancel()
        rearmTask = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        onAction = nil
        lastEmittedAction = nil
        if didActivateAudioSession {
            didActivateAudioSession = false
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }

    private func startSession() {
        let recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "ru_RU"))
            ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            AppLog.debug(.gesture, "awake_scroll_speech_unavailable")
            return
        }
        self.recognizer = recognizer
        AppLog.debug(
            .gesture,
            "awake_scroll_speech_locale",
            data: ["locale": locale.identifier]
        )

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.audioEngine = audioEngine
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            didActivateAudioSession = true
        } catch {
            AppLog.error(.gesture, "awake_scroll_audio_session", data: ["error": error.localizedDescription])
            return
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
            return
        }

        let capturedEpoch = epoch
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.epoch == capturedEpoch else { return }
                if let result {
                    self.considerTranscript(
                        result.bestTranscription.formattedString,
                        isFinal: result.isFinal,
                        epoch: capturedEpoch
                    )
                }
                if error != nil {
                    self.restartIfCurrent(epoch: capturedEpoch)
                }
            }
        }

        rearmTask?.cancel()
        rearmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 55_000_000_000)
            guard !Task.isCancelled else { return }
            self?.restartIfCurrent(epoch: capturedEpoch)
        }
    }

    private func considerTranscript(_ transcript: String, isFinal: Bool, epoch: UInt64) {
        let normalized = AwakeScrollVoiceClassifier.normalize(transcript)
        AppLog.debug(
            .gesture,
            "awake_scroll_voice_phrase",
            data: ["phrase": normalized, "final": isFinal ? "1" : "0"]
        )
        if lastEmittedAction != nil, AwakeScrollVoiceClassifier.match(normalized) == nil {
            lastEmittedAction = nil
        }
        guard let action = AwakeScrollVoiceClassifier.match(normalized) else {
            return
        }
        guard lastEmittedAction != action else { return }
        lastEmittedAction = action
        onAction?(action, epoch, normalized)
    }

    private func restartIfCurrent(epoch: UInt64) {
        guard self.epoch == epoch, onAction != nil else { return }
        let callback = onAction
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        task?.cancel()
        request?.endAudio()
        audioEngine = nil
        task = nil
        request = nil
        if let callback {
            start(epoch: epoch, locale: locale, onAction: callback)
        }
    }
}
