import UIKit
import XCTest
@testable import RecipeScalerNative

final class DetailScrollViewProbeTests: XCTestCase {
    func test_probe_inside_scroll_view_binds_that_scroll() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        let probe = DetailScrollViewProbe.ProbeView()
        let box = DetailScrollViewProbeBox()
        probe.box = box
        scroll.addSubview(probe)
        probe.discover()
        XCTAssertTrue(box.host === scroll)
    }

    func test_detached_probe_does_not_bind_another_window_scroll() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let other = UIScrollView(frame: window.bounds)
        other.contentSize = CGSize(width: 390, height: 2000)
        window.addSubview(other)
        let probe = DetailScrollViewProbe.ProbeView()
        let box = DetailScrollViewProbeBox()
        probe.box = box
        window.addSubview(probe)
        probe.discover()
        XCTAssertNil(box.host)
    }
}
