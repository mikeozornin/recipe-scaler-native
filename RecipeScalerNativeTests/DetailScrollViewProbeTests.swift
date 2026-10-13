import SwiftUI
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

    /// Spec 081 (T036): in the iPad two-column recipe the columns place the probe at the
    /// top of the steps, so hands-free scrolling moves the right column and leaves the left
    /// one. The recipe view only hands its probe box to the columns (`scrollProbe`), so this
    /// fails if the columns put the probe anywhere else.
    @MainActor
    func test_probe_in_two_columns_binds_the_right_column() throws {
        let box = DetailScrollViewProbeBox()
        let tall = { (label: String) in
            VStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { index in
                    Text(verbatim: "\(label) \(index)").frame(height: 60)
                }
            }
        }
        let host = UIHostingController(
            rootView: YDocRecipeDetailColumns(detailWidth: 900, scrollProbe: box) {
                tall("Ингредиент")
            } right: {
                tall("Шаг")
            }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 800))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.view.layoutIfNeeded()

        let scroll = try XCTUnwrap(box.host, "The probe found no scroll view")
        let frame = scroll.convert(scroll.bounds, to: window)
        let leftWidth = try XCTUnwrap(IPadLayoutPolicy.detailLeftWidth(detailWidth: 900))
        XCTAssertGreaterThanOrEqual(
            frame.minX,
            leftWidth,
            "Hands-free scrolling must move the steps column, not the left one: \(frame)"
        )
        XCTAssertGreaterThan(scroll.contentSize.height, frame.height, "The steps column must scroll")
    }
}
