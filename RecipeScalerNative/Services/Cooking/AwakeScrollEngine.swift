import CoreGraphics
import Foundation

struct AwakeScrollViewport: Equatable, Sendable {
    var boundsHeight: CGFloat
    var contentHeight: CGFloat
    var adjustedInsetTop: CGFloat
    var adjustedInsetBottom: CGFloat
    var contentOffsetY: CGFloat
}

enum AwakeScrollEngine {
    static let fraction: CGFloat = 0.75

    static func offsetY(action: AwakeScrollAction, viewport: AwakeScrollViewport) -> CGFloat {
        let y = viewport.contentOffsetY
        guard viewport.boundsHeight > 0 else { return y }
        let delta = fraction * viewport.boundsHeight
        let minOffset = -viewport.adjustedInsetTop
        let maxOffset = max(
            minOffset,
            viewport.contentHeight - viewport.boundsHeight + viewport.adjustedInsetBottom
        )
        switch action {
        case .up:
            return max(minOffset, y - delta)
        case .down:
            return min(maxOffset, y + delta)
        }
    }
}
