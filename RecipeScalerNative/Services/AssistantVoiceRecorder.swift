//
//  AssistantVoiceRecorder.swift
//  RecipeScalerNative
//
//  iOS-native voice capture for assistant transcribe (web parity: 120s client limit).
//

import AVFoundation
import Foundation

enum AssistantVoiceRecordingState: Sendable {
    case idle
    case recording
    case transcribing
}

enum AssistantVoiceRecorderError: LocalizedError {
    case permissionDenied
    case recordingFailed

    var errorDescriptionKey: String {
        switch self {
        case .permissionDenied:
            return "assistant.voice-error.permission-denied"
        case .recordingFailed:
            return "assistant.voice-error.recording"
        }
    }

    var errorDescription: String? {
        Bundle.currentLocalizedString(errorDescriptionKey)
    }
}

@MainActor
@Observable
final class AssistantVoiceRecorder {
    static let maxDuration: TimeInterval = 120
    /// Silence floor in dB for level normalization (averagePower is -160..0).
    private static let minPowerDb: Float = -45
    private static let meterPollIntervalNs: UInt64 = 50_000_000
    private static let maxSamples = 40

    private(set) var state: AssistantVoiceRecordingState = .idle
    private(set) var samples: [CGFloat] = []

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var autoStopTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?

    var onLimitReached: (() -> Void)?
    var onAutoStopCapture: ((Data) async -> Void)?

    func start() async throws {
        guard state == .idle else { return }

        let granted = await Self.requestRecordPermission()
        guard granted else {
            throw AssistantVoiceRecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("assistant-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AssistantVoiceRecorderError.recordingFailed
        }

        self.recorder = recorder
        recordingURL = url
        samples = []
        state = .recording

        startMetering()

        autoStopTask?.cancel()
        autoStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.maxDuration * 1_000_000_000))
            guard state == .recording else { return }
            onLimitReached?()
            do {
                let data = try await stopCapture()
                if let onAutoStopCapture {
                    await onAutoStopCapture(data)
                } else {
                    markIdle()
                }
            } catch {
                markIdle()
            }
        }
    }

    /// Stops capture and returns recorded audio bytes. Sets `transcribing` until `markIdle()`.
    func stopCapture() async throws -> Data {
        autoStopTask?.cancel()
        autoStopTask = nil
        stopMetering()

        recorder?.stop()
        recorder = nil

        defer {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        guard let url = recordingURL else {
            state = .idle
            throw AssistantVoiceRecorderError.recordingFailed
        }
        recordingURL = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            state = .idle
            throw AssistantVoiceRecorderError.recordingFailed
        }

        state = .transcribing
        let data = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)

        guard !data.isEmpty else {
            state = .idle
            throw AssistantVoiceRecorderError.recordingFailed
        }
        return data
    }

    func markIdle() {
        state = .idle
        samples = []
    }

    func cancel() {
        autoStopTask?.cancel()
        autoStopTask = nil
        stopMetering()
        recorder?.stop()
        recorder = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
        samples = []
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollMeter()
                try? await Task.sleep(nanoseconds: Self.meterPollIntervalNs)
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
    }

    private func pollMeter() {
        guard let recorder, state == .recording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = CGFloat(max((power - Self.minPowerDb) / -Self.minPowerDb, 0))
        let clamped = min(max(normalized, 0.08), 1)
        samples.append(clamped)
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
    }

    private static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
