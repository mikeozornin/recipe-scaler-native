import ARKit
import AVFoundation
import CoreMedia
import Foundation
import QuartzCore
import UIKit
import Vision

/// Non-MainActor owner so `deinit` stops camera/AR without a MainActor hop
/// onto a freed `AwakeScrollCaptureSession`.
final class AwakeScrollCaptureRuntime {
    var capture: AVCaptureSession?
    var arSession: ARSession?
    var thermalObserver: NSObjectProtocol?
    let visionQueue: DispatchQueue

    init(visionQueue: DispatchQueue) {
        self.visionQueue = visionQueue
    }

    deinit {
        tearDown()
    }

    func tearDown() {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
        thermalObserver = nil
        arSession?.delegate = nil
        arSession?.pause()
        arSession = nil
        if let capture {
            visionQueue.async {
                if capture.isRunning {
                    capture.stopRunning()
                }
            }
        }
        capture = nil
    }
}

@MainActor
final class AwakeScrollCaptureSession: NSObject {
    static var supportsFaceTracking: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    private let visionQueue = DispatchQueue(label: "ru.recipescaler.awake-scroll.vision")
    private lazy var runtime = AwakeScrollCaptureRuntime(visionQueue: visionQueue)
    private var epoch: UInt64 = 0
    private var modality: AwakeScrollCameraModality = .none
    private var onAction: ((AwakeScrollAction, UInt64) -> Void)?
    nonisolated(unsafe) private let classifierLock = NSLock()
    nonisolated(unsafe) private var hold = AwakeScrollHoldGate()
    nonisolated(unsafe) private var blinkState = AwakeScrollBlinkState()
    nonisolated(unsafe) private var captureModality: AwakeScrollCameraModality = .none
    nonisolated(unsafe) private let handPoseRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()
    /// Vision hand-pose sampling interval: 15 fps end-to-end (N4 battery budget).
    static let handPoseSampleInterval: TimeInterval = 1.0 / 15.0
    /// ARKit delivers face anchors at ~60 Hz. 30 Hz keeps wink rising-edges
    /// (often <100 ms) visible without hopping on every anchor.
    static let faceAnchorSampleInterval: TimeInterval = 1.0 / 30.0
    nonisolated(unsafe) private let visionThrottle = AwakeScrollVisionThrottle(
        minInterval: AwakeScrollCaptureSession.handPoseSampleInterval
    )
    nonisolated(unsafe) private let faceThrottle = AwakeScrollVisionThrottle(
        minInterval: AwakeScrollCaptureSession.faceAnchorSampleInterval
    )

    func start(
        modality: AwakeScrollCameraModality,
        epoch: UInt64,
        onAction: @escaping (AwakeScrollAction, UInt64) -> Void
    ) -> Bool {
        stop()
        guard modality != .none else { return false }
        self.modality = modality
        self.captureModality = modality
        self.epoch = epoch
        self.onAction = onAction
        classifierLock.lock()
        hold.reset()
        blinkState = AwakeScrollBlinkState()
        classifierLock.unlock()
        let started: Bool
        switch modality {
        case .face:
            started = startFace()
        case .hand:
            started = startHand()
        case .none:
            started = false
        }
        if started {
            startThermalObservation()
        } else {
            runtime.tearDown()
            self.onAction = nil
            self.modality = .none
            self.captureModality = .none
        }
        return started
    }

    func stop() {
        onAction = nil
        modality = .none
        captureModality = .none
        runtime.tearDown()
        classifierLock.lock()
        hold.reset()
        classifierLock.unlock()
        visionThrottle.reset()
        faceThrottle.reset()
        setThermalThrottle(nil)
    }

    /// Resets Vision/face sampling to the base budget (called from `stop()` and
    /// when thermal state returns to `.nominal`/`.fair`).
    nonisolated private func setThermalThrottle(_ fps: Double?) {
        let baseVision = AwakeScrollCaptureSession.handPoseSampleInterval
        let baseFace = AwakeScrollCaptureSession.faceAnchorSampleInterval
        if let fps {
            visionThrottle.updateMinInterval(Swift.max(baseVision, 1.0 / fps))
            faceThrottle.updateMinInterval(Swift.max(baseFace, 1.0 / fps))
        } else {
            visionThrottle.updateMinInterval(baseVision)
            faceThrottle.updateMinInterval(baseFace)
        }
    }

    private func emit(_ action: AwakeScrollAction) {
        onAction?(action, epoch)
    }

    private func startFace() -> Bool {
        guard ARFaceTrackingConfiguration.isSupported else {
            AppLog.debug(.gesture, "awake_scroll_face_unavailable")
            return false
        }
        let session = ARSession()
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        // Hand path matches device FPS to the sampler (`configureDeviceFrameRate`).
        // Face classification consumes 30 Hz. The iOS 26 SDK has no
        // `ARConfiguration.frameRate`; pick a 30 fps video format at the same
        // resolution so ARKit does not deliver the default ~60 Hz.
        let defaultResolution = config.videoFormat.imageResolution
        if let format = ARFaceTrackingConfiguration.supportedVideoFormats.first(where: {
            $0.framesPerSecond == 30 && $0.imageResolution == defaultResolution
        }) {
            config.videoFormat = format
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        runtime.arSession = session
        return true
    }

    private func startHand() -> Bool {
        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            AppLog.debug(.gesture, "awake_scroll_camera_unavailable")
            return false
        }
        guard session.canAddInput(input) else {
            AppLog.debug(.gesture, "awake_scroll_camera_input_rejected")
            return false
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: visionQueue)
        guard session.canAddOutput(output) else {
            AppLog.debug(.gesture, "awake_scroll_camera_output_rejected")
            return false
        }
        session.addOutput(output)
        output.connection(with: .video)?.isEnabled = true
        runtime.capture = session
        // Battery (N4): stream frames at the same rate the Vision throttle
        // consumes them, so the ISP is not delivering ~30 fps to have half
        // dropped by the throttle.
        configureDeviceFrameRate(device, fps: Int(thermalSampleFPS))
        visionQueue.async {
            session.startRunning()
        }
        return true
    }

    private var thermalSampleFPS: Double {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical ? 6 : 15
    }

    private func configureDeviceFrameRate(_ device: AVCaptureDevice, fps: Int) {
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains { range in
            CMTimeCompare(duration, range.minFrameDuration) >= 0
                && CMTimeCompare(duration, range.maxFrameDuration) <= 0
        }
        guard supported else {
            AppLog.debug(.gesture, "awake_scroll_frame_rate_unsupported")
            return
        }
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            AppLog.debug(.gesture, "awake_scroll_frame_duration_failed")
        }
    }

    /// Thermal response (N7): sampling slows to 6 fps while `thermalState`
    /// is `.serious`/`.critical`; otherwise restore the base budgets
    /// (hand 15 fps, face 30 fps).
    private func handleThermalStateChange() {
        let state = ProcessInfo.processInfo.thermalState
        if state == .serious || state == .critical {
            setThermalThrottle(6)
        } else {
            setThermalThrottle(nil)
        }
        if let device = currentVideoDevice() {
            configureDeviceFrameRate(device, fps: Int(thermalSampleFPS))
        }
    }

    private func currentVideoDevice() -> AVCaptureDevice? {
        let inputs = runtime.capture?.inputs.compactMap { $0 as? AVCaptureDeviceInput } ?? []
        return inputs.first?.device
    }

    private func startThermalObservation() {
        if let thermalObserver = runtime.thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            runtime.thermalObserver = nil
        }
        runtime.thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleThermalStateChange()
            }
        }
    }
}

extension AwakeScrollCaptureSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        // ARKit pushes anchors at ~60 Hz; sample at 30 fps (6 fps under
        // thermal throttling) before any MainActor hop.
        guard faceThrottle.shouldProcess(timestamp: CACurrentMediaTime()) else { return }
        let arkitLeft = face.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let arkitRight = face.blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        let blinks = AwakeScrollFaceClassifier.userSpaceBlinks(
            arkitLeft: arkitLeft,
            arkitRight: arkitRight
        )
        let now = Date()
        classifierLock.lock()
        let action: AwakeScrollAction?
        if captureModality == .face {
            action = AwakeScrollFaceClassifier.action(
                leftBlink: blinks.left,
                rightBlink: blinks.right,
                state: &blinkState,
                now: now
            )
        } else {
            action = nil
        }
        classifierLock.unlock()
        guard let action else { return }
        Task { @MainActor in
            self.emit(action)
        }
    }
}

extension AwakeScrollCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard visionThrottle.shouldProcess(timestamp: timestamp) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([handPoseRequest])
        guard let observation = handPoseRequest.results?.first else {
            classifierLock.lock()
            _ = hold.sample(nil, now: Date())
            classifierLock.unlock()
            return
        }
        let points = try? observation.recognizedPoints(.all)
        guard let tip = points?[.thumbTip],
              let cmc = points?[.thumbCMC],
              let wrist = points?[.wrist]
        else { return }
        let sample = AwakeScrollHandSample(
            thumbTip: CGPoint(x: tip.location.x, y: 1 - tip.location.y),
            thumbBase: CGPoint(x: cmc.location.x, y: 1 - cmc.location.y),
            wrist: CGPoint(x: wrist.location.x, y: 1 - wrist.location.y),
            tipConfidence: Float(tip.confidence),
            baseConfidence: Float(cmc.confidence),
            wristConfidence: Float(wrist.confidence)
        )
        let classified = AwakeScrollHandClassifier.action(from: sample)
        classifierLock.lock()
        let action: AwakeScrollAction?
        if captureModality == .hand {
            action = hold.sample(classified, now: Date())
        } else {
            action = nil
        }
        classifierLock.unlock()
        guard let action else { return }
        Task { @MainActor in
            self.emit(action)
        }
    }
}

/// Drops camera frames before Vision so the pose request stays within the
/// battery budget (15 fps base, 6 fps under serious/critical thermal state).
final class AwakeScrollVisionThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTimestamp: TimeInterval = 0
    private var minInterval: TimeInterval

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// Updates the sampling budget (thermal response raises it, recovery lowers it).
    func updateMinInterval(_ newInterval: TimeInterval) {
        lock.lock()
        minInterval = newInterval
        lock.unlock()
    }

    func shouldProcess(timestamp: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if lastTimestamp > 0, timestamp - lastTimestamp < minInterval {
            return false
        }
        lastTimestamp = timestamp
        return true
    }

    func reset() {
        lock.lock()
        lastTimestamp = 0
        lock.unlock()
    }
}
