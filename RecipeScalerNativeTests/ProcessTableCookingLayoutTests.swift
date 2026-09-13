import SwiftUI
import UIKit
import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

/// Hosts the cooking matrix in a `UIWindow` without launching the app shell.
/// Catches the SwiftUI `view origin is invalid: (…, inf)` trap and a cover
/// that layouts then dismisses itself.
@MainActor
final class ProcessTableCookingLayoutTests: XCTestCase {
    func testCookingViewLaysOutFiniteFramesAndShowsGrid() {
        let host = UIHostingController(rootView: makeCookingView())
        let window = makeWindow(size: CGSize(width: 420, height: 756))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        pumpMain(seconds: 0.25)

        XCTAssertTrue(
            viewTreeHasFiniteFrames(host.view),
            "Cooking layout must keep every UIView frame finite (no inf/NaN origin)"
        )
        XCTAssertTrue(
            containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableGrid,
                in: host.view
            ),
            "After layout the process-table grid must be in the hierarchy"
        )
        XCTAssertTrue(
            containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableClose,
                in: host
            ),
            "Close must be reachable in the cooking chrome"
        )
    }

    func testCheckboxPointSizeMatchesIngredientsListMarker() {
        XCTAssertEqual(
            ProcessTableLayout.checkboxPointSize,
            RecipeRowLayoutMetrics.titleFontSize,
            "Process-table checkboxes must match the ingredients/shopping list marker size"
        )
        XCTAssertEqual(
            ProcessTableLayout.checkboxPointSize,
            AppTypography.bodySize,
            "Timer-chip alarm uses checkboxPointSize so it matches circles/checkmarks"
        )
    }

    func testIngredientRowHeightIncludesVerticalPadAroundThumb() {
        XCTAssertEqual(ProcessTableLayout.cellTextVerticalPad, 4)
        XCTAssertEqual(ProcessTableLayout.ingredientRowVerticalPad, 6)
        let paddedThumb =
            ProcessTableLayout.illustrationSlot + ProcessTableLayout.ingredientRowVerticalPad * 2
        XCTAssertGreaterThan(
            paddedThumb,
            ProcessTableLayout.rowMinHeight,
            "4 pt pad above and below the 40 pt thumb must not be clipped by rowMinHeight"
        )
    }

    func testIngredientAmountOmitsUnitAlreadyInTheName() {
        let ingredient = IngredientData(
            id: "cream",
            name: "Кремчиз ком. тем-ры, кг",
            originalAmount: "1",
            unit: "кг"
        )
        XCTAssertEqual(
            ProcessTableIngredientLabel.display(ingredient, scaleFactor: 1),
            "Кремчиз ком. тем-ры, кг 1"
        )
    }

    func testStaleBannerRowIsFootnoteHeight() {
        XCTAssertEqual(ProcessTableLayout.staleBannerToContentGap, 8)
        XCTAssertEqual(
            ProcessTableLayout.ctaMinHit + ProcessTableLayout.bannerHitVerticalCollapse * 2,
            ProcessTableLayout.bannerLineHeight,
            accuracy: 0.5,
            "Rebuild hit is 44 pt but the banner row must collapse to the footnote line"
        )
    }

    func testCookingUsesFullWidthWithTightHorizontalPad() {
        XCTAssertEqual(ProcessTableLayout.cellTextHorizontalPad, 10)
        XCTAssertEqual(ProcessTableLayout.cookingHorizontalEdgePad, 8)
        XCTAssertEqual(ProcessTableLayout.cookingLeadingEdgePad, 24)
        XCTAssertEqual(ProcessTableLayout.cookingTrailingEdgePad, 0)
        XCTAssertEqual(ProcessTableLayout.cookingCloseTrailingPad, 28)
        XCTAssertEqual(ProcessTableLayout.cookingCloseTopPad, 10)
        XCTAssertEqual(ProcessTableLayout.timerChipGap, 4)
        XCTAssertEqual(ProcessTableLayout.timerChipHorizontalPad, 8)
        XCTAssertEqual(ProcessTableLayout.timerChipVerticalPad, 6)
        XCTAssertLessThan(
            ProcessTableLayout.cookingHorizontalEdgePad,
            ProcessTableLayout.matrixPadding,
            "Cooking trailing pad must be tighter than the recipe-card matrix gutter"
        )
    }

    func testCookingHostReportsLandscapeSupport() {
        let host = UIHostingController(rootView: makeCookingView())
        _ = host.view
        let mask = host.supportedInterfaceOrientations
        XCTAssertTrue(
            mask.contains(.landscapeLeft) && mask.contains(.landscapeRight),
            "Cooking host must advertise landscape so requestGeometryUpdate is not rejected as portrait-only; got \(mask)"
        )
    }

    func testPresentedCookingCoverStaysPresentedAfterLayout() {
        let window = makeWindow(size: CGSize(width: 420, height: 756))
        let presenter = PortraitLockedController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        presenter.view.layoutIfNeeded()

        let host = UIHostingController(rootView: makeCookingView())
        host.modalPresentationStyle = .fullScreen

        let presented = expectation(description: "cooking presented")
        presenter.present(host, animated: false) {
            presented.fulfill()
        }
        wait(for: [presented], timeout: 2)

        host.view.layoutIfNeeded()
        pumpMain(seconds: 0.4)

        XCTAssertEqual(
            presenter.presentedViewController,
            host,
            "Cooking host must stay presented after layout; geometry failure must not dismiss"
        )
        XCTAssertTrue(
            viewTreeHasFiniteFrames(host.view),
            "Presented cooking view must layout with finite frames"
        )
        XCTAssertTrue(
            containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableGrid,
                in: host.view
            )
        )
    }

    // MARK: - Fixture

    private func makeCookingView() -> ProcessTableCookingView {
        let ingredients: [IngredientData] = (0..<6).map { index in
            IngredientData(
                id: "ing\(index)",
                name: "Ingredient \(index)",
                originalAmount: "100",
                unit: "g",
                order: index + 1
            )
        }
        let hash = ProcessTableSourceHash.hash(
            ingredients: ingredients,
            descriptionHtml: "<ol><li>Mix</li><li>Bake</li></ol>"
        )
        let columns = (0..<6).map { index in
            """
            {"id":"c\(index)","title":"Step \(index)","kind":"cook","stepIndex":\(index)}
            """
        }.joined(separator: ",")
        let assignments = (0..<6).map { index in
            "{\"ingredientId\":\"ing\(index)\",\"columnId\":\"c\(index)\"}"
        }.joined(separator: ",")
        let recipe = RecipeData(
            id: "layout-test",
            name: "Layout loaf",
            servings: 1,
            color: "#3b82f6",
            version: "v3",
            description: "<ol><li>Mix</li><li>Bake</li></ol>",
            ingredients: ingredients,
            nutrition: nil,
            isPublic: false,
            hasSteps: true,
            createdAt: "",
            updatedAt: "",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil,
            processTableRaw: """
            {"version":1,"sourceHash":"\(hash)","columns":[\(columns)],"assignments":[\(assignments)]}
            """
        )
        return ProcessTableCookingView(
            recipe: recipe,
            scaleFactor: 1,
            allowsRebuild: false,
            restoreAwakeOnDismiss: false,
            session: ProcessTableCookingSession(),
            rebuildModel: ProcessTableRebuildModel()
        )
    }

    private func makeWindow(size: CGSize) -> UIWindow {
        let window = PassthroughWindow(frame: CGRect(origin: .zero, size: size))
        window.isHidden = false
        return window
    }

    private func pumpMain(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func viewTreeHasFiniteFrames(_ view: UIView) -> Bool {
        let frame = view.frame
        let originFinite = frame.origin.x.isFinite && frame.origin.y.isFinite
        let sizeFinite = frame.size.width.isFinite && frame.size.height.isFinite
        guard originFinite, sizeFinite else { return false }
        return view.subviews.allSatisfy(viewTreeHasFiniteFrames)
    }

    private func containsAccessibilityIdentifier(_ id: String, in view: UIView) -> Bool {
        if view.accessibilityIdentifier == id { return true }
        if let elements = view.accessibilityElements {
            for element in elements {
                if (element as? NSObject)?.value(forKey: "accessibilityIdentifier") as? String == id {
                    return true
                }
            }
        }
        return view.subviews.contains { containsAccessibilityIdentifier(id, in: $0) }
    }

    private func containsAccessibilityIdentifier(_ id: String, in controller: UIViewController) -> Bool {
        if containsAccessibilityIdentifier(id, in: controller.view) { return true }
        let barItems =
            (controller.navigationItem.leftBarButtonItems ?? [])
            + (controller.navigationItem.rightBarButtonItems ?? [])
        if barItems.contains(where: { $0.accessibilityIdentifier == id }) {
            return true
        }
        if controller.children.contains(where: { containsAccessibilityIdentifier(id, in: $0) }) {
            return true
        }
        if let presented = controller.presentedViewController,
           containsAccessibilityIdentifier(id, in: presented) {
            return true
        }
        return false
    }
}

private final class PortraitLockedController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }
}

private final class PassthroughWindow: UIWindow {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
