import UIKit
import XCTest
@testable import RecipeScalerNative

@MainActor
final class ProcessTableCookingOrientationTests: XCTestCase {
    func testPortraitDuringCookingReassertsLandscape() {
        let gate = ProcessTableCookingOrientationGate()
        XCTAssertEqual(gate.apply(.portrait), .reassertLandscape)
        XCTAssertEqual(gate.apply(.landscapeLeft), .stay)
        XCTAssertEqual(gate.apply(.portrait), .reassertLandscape)
    }

    func testLandscapeStays() {
        let gate = ProcessTableCookingOrientationGate()
        XCTAssertEqual(gate.apply(.landscapeLeft), .stay)
        XCTAssertEqual(gate.apply(.landscapeRight), .stay)
    }

    func testUnknownStays() {
        let gate = ProcessTableCookingOrientationGate()
        XCTAssertEqual(gate.apply(.unknown), .stay)
    }

    func testWindowSizeInfersInterfaceOrientation() {
        XCTAssertEqual(
            ProcessTableCookingOrientationGate.interfaceOrientation(
                from: CGSize(width: 852, height: 393)
            ),
            .landscapeLeft
        )
        XCTAssertEqual(
            ProcessTableCookingOrientationGate.interfaceOrientation(
                from: CGSize(width: 393, height: 852)
            ),
            .portrait
        )
        XCTAssertNil(
            ProcessTableCookingOrientationGate.interfaceOrientation(
                from: CGSize(width: 420, height: 56)
            )
        )
    }

    func testPortraitWindowSizeDoesNotDismiss() {
        let gate = ProcessTableCookingOrientationGate()
        let landscape = ProcessTableCookingOrientationGate.interfaceOrientation(
            from: CGSize(width: 852, height: 393)
        )!
        let portrait = ProcessTableCookingOrientationGate.interfaceOrientation(
            from: CGSize(width: 393, height: 852)
        )!
        XCTAssertEqual(gate.apply(landscape), .stay)
        XCTAssertEqual(gate.apply(portrait), .reassertLandscape)
    }

    func testPortraitWindowSizeIsNotAcceptedForLayout() {
        let landscape = CGSize(width: 852, height: 393)
        let portrait = CGSize(width: 393, height: 852)
        XCTAssertEqual(
            ProcessTableCookingOrientationGate.acceptedLayoutSize(landscape, idiom: .phone),
            landscape
        )
        XCTAssertNil(
            ProcessTableCookingOrientationGate.acceptedLayoutSize(portrait, idiom: .phone)
        )
        XCTAssertEqual(
            ProcessTableCookingOrientationGate.acceptedLayoutSize(portrait, idiom: .pad),
            portrait
        )
        XCTAssertNil(
            ProcessTableCookingOrientationGate.acceptedLayoutSize(
                CGSize(width: 420, height: 56),
                idiom: .phone
            )
        )
    }
}
