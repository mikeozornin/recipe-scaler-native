import XCTest
@testable import RecipeScalerNative

final class AwakeScrollFaceClassifierTests: XCTestCase {
    func test_left_up() {
        var state = AwakeScrollBlinkState()
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(leftBlink: 0.1, rightBlink: 0.1, state: &state)
        )
        XCTAssertEqual(
            AwakeScrollFaceClassifier.action(leftBlink: 0.9, rightBlink: 0.1, state: &state),
            .up
        )
    }

    func test_right_down() {
        var state = AwakeScrollBlinkState()
        XCTAssertEqual(
            AwakeScrollFaceClassifier.action(leftBlink: 0.1, rightBlink: 0.95, state: &state),
            .down
        )
    }

    func test_double_blink_ignore() {
        var state = AwakeScrollBlinkState()
        XCTAssertNil(
            AwakeScrollFaceClassifier.action(leftBlink: 0.9, rightBlink: 0.9, state: &state)
        )
    }
}
