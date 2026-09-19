import XCTest
@testable import RecipeScalerNative

final class AwakeScrollEngineTests: XCTestCase {
    func test_down_scrolls_75_percent() {
        let viewport = AwakeScrollViewport(
            boundsHeight: 400,
            contentHeight: 4000,
            adjustedInsetTop: 0,
            adjustedInsetBottom: 0,
            contentOffsetY: 0
        )
        XCTAssertEqual(AwakeScrollEngine.offsetY(action: .down, viewport: viewport), 300)
    }

    func test_down_clamps_end_with_insets() {
        let viewport = AwakeScrollViewport(
            boundsHeight: 400,
            contentHeight: 500,
            adjustedInsetTop: 88,
            adjustedInsetBottom: 34,
            contentOffsetY: 80
        )
        XCTAssertEqual(AwakeScrollEngine.offsetY(action: .down, viewport: viewport), 134)
    }

    func test_down_near_bottom_does_not_pass_uikit_max() {
        let viewport = AwakeScrollViewport(
            boundsHeight: 800,
            contentHeight: 1200,
            adjustedInsetTop: 100,
            adjustedInsetBottom: 40,
            contentOffsetY: 390
        )
        let y = AwakeScrollEngine.offsetY(action: .down, viewport: viewport)
        XCTAssertEqual(y, 440)
        XCTAssertLessThanOrEqual(
            y,
            viewport.contentHeight - viewport.boundsHeight + viewport.adjustedInsetBottom
        )
    }

    func test_up_clamps_start() {
        let viewport = AwakeScrollViewport(
            boundsHeight: 400,
            contentHeight: 4000,
            adjustedInsetTop: 0,
            adjustedInsetBottom: 0,
            contentOffsetY: 0
        )
        XCTAssertEqual(AwakeScrollEngine.offsetY(action: .up, viewport: viewport), 0)
    }

    func test_zero_height_noop() {
        let viewport = AwakeScrollViewport(
            boundsHeight: 0,
            contentHeight: 4000,
            adjustedInsetTop: 0,
            adjustedInsetBottom: 0,
            contentOffsetY: 80
        )
        XCTAssertEqual(AwakeScrollEngine.offsetY(action: .down, viewport: viewport), 80)
    }
}
