import XCTest
@testable import RecipeScalerNative

final class AwakeScrollHandClassifierTests: XCTestCase {
    func test_hand_up_once() {
        let sample = AwakeScrollHandSample(
            thumbTip: CGPoint(x: 0.5, y: 0.2),
            thumbBase: CGPoint(x: 0.5, y: 0.5),
            wrist: CGPoint(x: 0.5, y: 0.85),
            tipConfidence: 0.9,
            baseConfidence: 0.9,
            wristConfidence: 0.9
        )
        XCTAssertEqual(AwakeScrollHandClassifier.action(from: sample), .up)

        var gate = AwakeScrollHoldGate(holdDuration: 0.2)
        let t0 = Date()
        XCTAssertNil(gate.sample(AwakeScrollAction.up, now: t0))
        XCTAssertNil(gate.sample(AwakeScrollAction.up, now: t0.addingTimeInterval(0.1)))
        XCTAssertEqual(gate.sample(AwakeScrollAction.up, now: t0.addingTimeInterval(0.2)), .up)
        XCTAssertNil(gate.sample(AwakeScrollAction.up, now: t0.addingTimeInterval(0.3)))
    }

    func test_dead_zone() {
        let sample = AwakeScrollHandSample(
            thumbTip: CGPoint(x: 0.5, y: 0.5),
            thumbBase: CGPoint(x: 0.5, y: 0.52),
            wrist: CGPoint(x: 0.5, y: 0.85),
            tipConfidence: 0.9,
            baseConfidence: 0.9,
            wristConfidence: 0.9
        )
        XCTAssertNil(AwakeScrollHandClassifier.action(from: sample))
    }

    func test_fist_ignored() {
        let sample = AwakeScrollHandSample(
            thumbTip: CGPoint(x: 0.5, y: 0.58),
            thumbBase: CGPoint(x: 0.5, y: 0.5),
            wrist: CGPoint(x: 0.5, y: 0.85),
            tipConfidence: 0.9,
            baseConfidence: 0.9,
            wristConfidence: 0.9
        )
        XCTAssertNil(AwakeScrollHandClassifier.action(from: sample))
    }
}
