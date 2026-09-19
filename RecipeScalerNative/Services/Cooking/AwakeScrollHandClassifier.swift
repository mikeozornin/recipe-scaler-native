import CoreGraphics
import Foundation

struct AwakeScrollHandSample: Equatable, Sendable {
    var thumbTip: CGPoint
    var thumbBase: CGPoint
    var wrist: CGPoint
    var tipConfidence: Float
    var baseConfidence: Float
    var wristConfidence: Float
}

struct AwakeScrollHoldGate {
    var holdDuration: TimeInterval
    private var candidate: AwakeScrollAction?
    private var since: Date?
    private var didFire = false

    init(holdDuration: TimeInterval = 0.2) {
        self.holdDuration = holdDuration
    }

    mutating func sample(_ action: AwakeScrollAction?, now: Date) -> AwakeScrollAction? {
        guard let action else {
            candidate = nil
            since = nil
            didFire = false
            return nil
        }
        if candidate != action {
            candidate = action
            since = now
            didFire = false
            return nil
        }
        guard !didFire, let since, now.timeIntervalSince(since) >= holdDuration else {
            return nil
        }
        didFire = true
        return action
    }

    mutating func reset() {
        candidate = nil
        since = nil
        didFire = false
    }
}

enum AwakeScrollHandClassifier {
    static let deadZone: CGFloat = 0.08
    static let minConfidence: Float = 0.3

    /// UIKit-like points: smaller `y` is higher on screen → `.up`.
    static func action(from sample: AwakeScrollHandSample) -> AwakeScrollAction? {
        guard sample.tipConfidence >= minConfidence,
              sample.baseConfidence >= minConfidence,
              sample.wristConfidence >= minConfidence
        else { return nil }
        let tipFromWrist = hypot(sample.thumbTip.x - sample.wrist.x, sample.thumbTip.y - sample.wrist.y)
        let baseFromWrist = hypot(sample.thumbBase.x - sample.wrist.x, sample.thumbBase.y - sample.wrist.y)
        guard tipFromWrist > baseFromWrist else { return nil }
        let dy = sample.thumbTip.y - sample.thumbBase.y
        if dy < -deadZone { return .up }
        if dy > deadZone { return .down }
        return nil
    }
}
