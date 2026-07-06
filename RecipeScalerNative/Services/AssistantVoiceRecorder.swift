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
    /// Tape meter: one bar appended per N meter polls (≈200ms per bar at 50ms poll).
    private static let barsPerSample = 4
    /// Tape window length in bars. Generously larger than any realistic visible bar count so
    /// the meter never shows trailing silence placeholders on the left after long recordings.
    /// At one bar per 200ms this is ~40s of recording; max record duration is 120s, but visible
    /// bar count onscreen is well under 100, so we trim to display-size downstream anyway.
    private static let meterBarWindow: Int = 200
    /// Meter geometry, web parity (`VOICE_METER_*_PX`).
    static let meterBarWidth: CGFloat = 2
    static let meterBarSpacing: CGFloat = 2
    static let meterMinHeight: CGFloat = 3
    static let meterMaxHeight: CGFloat = 24
    /// Below this normalized level the bar stays at `meterMinHeight` (web `VOICE_METER_MIN_SCALE = 0.12`).
    private static let meterMinScale: CGFloat = 0.12

    private(set) var state: AssistantVoiceRecordingState = .idle
    /// Precomputed tape-meter bar heights in pt, newest last. Each bar keeps its
    /// height once recorded (web parity: peak RMS scrolls right→left, stable height).
    private(set) var barHeights: [CGFloat] = []

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var autoStopTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    /// In-flight transcription; cancelled by `cancel()` so a late server reply can't
    /// overwrite the composer text after the user abandoned the recording.
    internal(set) var transcriptionTask: Task<Void, Never>?
    /// Counter of meter polls since the last tape bar was committed.
    private var pollsSinceLastBar: Int = 0
    /// Max normalized level seen since the last tape bar was committed (web peak-RMS parity).
    private var peakSinceLastBar: CGFloat = AssistantVoiceRecorder.meterMinScale

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
        barHeights = []
        pollsSinceLastBar = 0
        peakSinceLastBar = Self.meterMinScale
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
    /// Caller is responsible for assigning the returned data to `transcriptionTask` so that
    /// `cancel()` can abort an in-flight upload.
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
            reset()
            throw AssistantVoiceRecorderError.recordingFailed
        }
        recordingURL = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            reset()
            throw AssistantVoiceRecorderError.recordingFailed
        }

        state = .transcribing
        // Sweep the temp file regardless of read success so a disk error can't strand PII.
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)

        guard !data.isEmpty else {
            reset()
            throw AssistantVoiceRecorderError.recordingFailed
        }
        return data
    }

    /// Resets to `.idle`, drops meter history, and stops all background work except the
    /// transcription task (use `cancel()` to abort an in-flight transcription).
    func markIdle() {
        reset()
    }

    /// Aborts everything: capture, auto-stop, metering, AND in-flight transcription.
    /// Safe to call from any state (idle / recording / transcribing).
    func cancel() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        reset()
    }

    private func reset() {
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
        pollsSinceLastBar = 0
        peakSinceLastBar = Self.meterMinScale
        state = .idle
        barHeights = []
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
        let clamped = min(max(normalized, Self.meterMinScale), 1)
        if clamped > peakSinceLastBar {
            peakSinceLastBar = clamped
        }
        pollsSinceLastBar += 1
        if pollsSinceLastBar >= Self.barsPerSample {
            commitBar(for: peakSinceLastBar)
            pollsSinceLastBar = 0
            peakSinceLastBar = Self.meterMinScale
        }
    }

    private func commitBar(for normalizedLevel: CGFloat) {
        let amplified = pow(normalizedLevel, 0.65)
        let height = Self.meterMinHeight + amplified * (Self.meterMaxHeight - Self.meterMinHeight)
        barHeights.append(height)
        // Bounded ring at 200 entries; removeFirst is O(n) but at ≤200 CGFloats per ~200ms push
        // this is sub-microsecond work — not worth a wrap-around buffer's indexing complexity.
        if barHeights.count > Self.meterBarWindow {
            barHeights.removeFirst(barHeights.count - Self.meterBarWindow)
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
