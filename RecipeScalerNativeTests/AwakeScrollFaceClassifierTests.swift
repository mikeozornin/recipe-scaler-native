import XCTest
@testable import RecipeScalerNative

final class AwakeScrollFaceClassifierTests: XCTestCase {
    func test_arkit_front_camera_mirrors_user_left_right() {
        let mapped = AwakeScrollFaceClassifier.userSpaceBlinks(arkitLeft: 0.9, arkitRight: 0.1)
        XCTAssertEqual(mapped.left, 0.1)
        XCTAssertEqual(mapped.right, 0.9)
        var state = AwakeScrollBlinkState()
        XCTAssertEqual(
            AwakeScrollFaceClassifier.action(
                leftBlink: mapped.left,
                rightBlink: mapped.right,
                state: &state
            ),
            .down
        )
    }

    func test_left_wink_fires_immediately_when_right_open() {
        var state = AwakeScrollBlinkState()
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(leftBlink: 0.1, rightBlink: 0.1, state: &state)
        )
        XCTAssertEqual(
            AwakeScrollFaceClassifier.action(leftBlink: 0.9, rightBlink: 0.1, state: &state),
            .up
        )
    }

    func test_right_wink_fires_immediately_when_left_open() {
        var state = AwakeScrollBlinkState()
        XCTAssertEqual(
            AwakeScrollFaceClassifier.action(leftBlink: 0.1, rightBlink: 0.95, state: &state),
            .down
        )
    }

    func test_double_blink_same_sample_ignore() {
        var state = AwakeScrollBlinkState()
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(leftBlink: 0.9, rightBlink: 0.9, state: &state)
        )
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(
                leftBlink: 0.9,
                rightBlink: 0.9,
                state: &state,
                now: Date().addingTimeInterval(0.2)
            )
        )
    }

    func test_double_blink_50ms_apart_ignore() {
        var state = AwakeScrollBlinkState()
        let t0 = Date()
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(
                leftBlink: 0.9,
                rightBlink: 0.5,
                state: &state,
                now: t0
            )
        )
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(
                leftBlink: 0.9,
                rightBlink: 0.9,
                state: &state,
                now: t0.addingTimeInterval(0.05)
            )
        )
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(
                leftBlink: 0.9,
                rightBlink: 0.9,
                state: &state,
                now: t0.addingTimeInterval(0.2)
            )
        )
    }

    func test_asymmetric_pending_flushes_after_window() {
        var state = AwakeScrollBlinkState()
        let t0 = Date()
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(
                leftBlink: 0.9,
                rightBlink: 0.5,
                state: &state,
                now: t0
            )
        )
        XCTAssertEqual(
            AwakeScrollFaceClassifier.action(
                leftBlink: 0.9,
                rightBlink: 0.4,
                state: &state,
                now: t0.addingTimeInterval(0.1)
            ),
            .up
        )
    }
}
