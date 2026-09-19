import ARKit
import AVFoundation
import CoreMedia
import Foundation
import UIKit
import Vision

@MainActor
final class AwakeScrollCaptureSession: NSObject {
    static var supportsFaceTracking: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    private var capture: AVCaptureSession?
    private var arSession: ARSession?
    private var epoch: UInt64 = 0
    private var modality: AwakeScrollCameraModality = .none
    private var onAction: ((AwakeScrollAction, UInt64) -> Void)?
    private var hold = AwakeScrollHoldGate()
    private var blinkState = AwakeScrollBlinkState()
    private let visionQueue = DispatchQueue(label: "ru.recipescaler.awake-scroll.vision")
    nonisolated(unsafe) private let visionThrottle = AwakeScrollVisionThrottle(minInterval: 1.0 / 20.0)

    func start(
        modality: AwakeScrollCameraModality,
        epoch: UInt64,
        onAction: @escaping (AwakeScrollAction, UInt64) -> Void
    ) {
        stop()
        guard modality != .none else { return }
        self.modality = modality
        self.epoch = epoch
        self.onAction = onAction
        hold.reset()
        blinkState = AwakeScrollBlinkState()
        switch modality {
        case .face:
            startFace()
        case .hand:
            startHand()
        case .none:
            break
        }
    }

    func stop() {
        onAction = nil
        arSession?.pause()
        arSession = nil
        if let capture, capture.isRunning {
            visionQueue.async {
                capture.stopRunning()
            }
        }
        capture = nil
        hold.reset()
        visionThrottle.reset()
    }

    private func emit(_ action: AwakeScrollAction) {
        onAction?(action, epoch)
    }

    private func startFace() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let session = ARSession()
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arSession = session
    }

    private func startHand() {
        let session = AVCaptureSession()
        session.sessionPreset = .vga640x480
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        if session.canAddInput(input) {
            session.addInput(input)
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: visionQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        output.connection(with: .video)?.isEnabled = true
        capture = session
        visionQueue.async {
            session.startRunning()
        }
    }
}

extension AwakeScrollCaptureSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let left = face.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let right = face.blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        Task { @MainActor in
            guard self.modality == .face else { return }
            if let action = AwakeScrollFaceClassifier.action(
                leftBlink: left,
                rightBlink: right,
                state: &self.blinkState
            ) {
                self.emit(action)
            }
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

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([request])
        guard let observation = request.results?.first else {
            Task { @MainActor in
                _ = self.hold.sample(nil, now: Date())
            }
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
        Task { @MainActor in
            guard self.modality == .hand else { return }
            let now = Date()
            let classified = AwakeScrollHandClassifier.action(from: sample)
            if let action = self.hold.sample(classified, now: now) {
                self.emit(action)
            }
        }
    }
}

/// Drops camera frames before Vision so the pose request stays ≤20 fps.
final class AwakeScrollVisionThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTimestamp: TimeInterval = 0
    private let minInterval: TimeInterval

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
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
