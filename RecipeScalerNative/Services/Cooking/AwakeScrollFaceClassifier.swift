import Foundation

struct AwakeScrollBlinkState: Equatable, Sendable {
    var leftWasBelow = true
    var rightWasBelow = true
}

enum AwakeScrollFaceClassifier {
    static let blinkThreshold: Float = 0.6

    /// Left rising edge → `.up`, right → `.down`. Both in one sample → ignore.
    static func action(
        leftBlink: Float,
        rightBlink: Float,
        state: inout AwakeScrollBlinkState
    ) -> AwakeScrollAction? {
        let leftNow = leftBlink >= blinkThreshold
        let rightNow = rightBlink >= blinkThreshold
        let leftEdge = leftNow && state.leftWasBelow
        let rightEdge = rightNow && state.rightWasBelow
        state.leftWasBelow = !leftNow
        state.rightWasBelow = !rightNow
        if leftEdge && rightEdge { return nil }
        if leftEdge { return .up }
        if rightEdge { return .down }
        return nil
    }
}
