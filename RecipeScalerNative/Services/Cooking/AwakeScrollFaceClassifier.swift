import Foundation

struct AwakeScrollBlinkState: Equatable, Sendable {
    var leftWasBelow = true
    var rightWasBelow = true
    var pendingAction: AwakeScrollAction?
    var pendingAt: Date?
}

enum AwakeScrollFaceClassifier {
    static let blinkThreshold: Float = 0.6
    /// Other eye is clearly open → treat as a wink, not the start of a blink.
    static let contralateralOpenThreshold: Float = 0.35
    /// Both-eyes window from `gesture-mapping.md`: a natural blink must not fire.
    static let bothEyesIgnoreWindow: TimeInterval = 0.1

    /// ARKit `.userFacing` labels `eyeBlinkLeft` as the eye on the camera's
    /// left — the user's anatomical **right**. Undo that mirror so `leftBlink`
    /// is always "my left eye".
    static func userSpaceBlinks(arkitLeft: Float, arkitRight: Float) -> (left: Float, right: Float) {
        (left: arkitRight, right: arkitLeft)
    }

    /// Left rising edge → `.up`, right → `.down`.
    /// Fire immediately when the other eye is clearly open; otherwise wait
    /// `bothEyesIgnoreWindow` so a conjugate blink can cancel.
    static func action(
        leftBlink: Float,
        rightBlink: Float,
        state: inout AwakeScrollBlinkState,
        now: Date = Date()
    ) -> AwakeScrollAction? {
        let leftNow = leftBlink >= blinkThreshold
        let rightNow = rightBlink >= blinkThreshold
        let leftEdge = leftNow && state.leftWasBelow
        let rightEdge = rightNow && state.rightWasBelow
        state.leftWasBelow = !leftNow
        state.rightWasBelow = !rightNow

        if leftEdge && rightEdge {
            clearPending(&state)
            return nil
        }

        if leftEdge {
            if rightBlink < contralateralOpenThreshold {
                clearPending(&state)
                return .up
            }
            return noteEdge(.up, state: &state, now: now)
        }
        if rightEdge {
            if leftBlink < contralateralOpenThreshold {
                clearPending(&state)
                return .down
            }
            return noteEdge(.down, state: &state, now: now)
        }
        return flushPendingIfElapsed(&state, now: now)
    }

    private static func noteEdge(
        _ action: AwakeScrollAction,
        state: inout AwakeScrollBlinkState,
        now: Date
    ) -> AwakeScrollAction? {
        if let pending = state.pendingAction,
           pending != action,
           let pendingAt = state.pendingAt,
           now.timeIntervalSince(pendingAt) < bothEyesIgnoreWindow {
            clearPending(&state)
            return nil
        }
        state.pendingAction = action
        state.pendingAt = now
        return nil
    }

    private static func flushPendingIfElapsed(
        _ state: inout AwakeScrollBlinkState,
        now: Date
    ) -> AwakeScrollAction? {
        guard let pending = state.pendingAction, let pendingAt = state.pendingAt else {
            return nil
        }
        guard now.timeIntervalSince(pendingAt) >= bothEyesIgnoreWindow else {
            return nil
        }
        clearPending(&state)
        return pending
    }

    private static func clearPending(_ state: inout AwakeScrollBlinkState) {
        state.pendingAction = nil
        state.pendingAt = nil
    }
}
