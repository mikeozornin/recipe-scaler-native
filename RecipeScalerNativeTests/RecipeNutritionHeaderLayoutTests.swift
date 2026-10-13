import SwiftUI
import UIKit
import XCTest
@testable import RecipeScalerNative

/// «КБЖУ на» and the basis selector (spec 081, 2026-10-13). The selector never gets narrower
/// than its titles; a row wider than the column made the recipe's vertical `ScrollView`
/// re-center its content, so the whole column shifted left and clipped. The selector now
/// moves under the title when the row can't fit (one line from 391 pt in en, 374 in ru).
@MainActor
final class RecipeNutritionHeaderLayoutTests: XCTestCase {
    /// The block's own side insets (`.padding(.horizontal)`).
    private let inset: CGFloat = 16

    override func setUp() {
        super.setUp()
        Bundle.installLanguageOverrideSwizzle()
    }

    override func tearDown() {
        AppLanguagePreference.apply(AppLanguagePreference.current)
        super.tearDown()
    }

    /// iPhone widths and the iPad recipe column (399 at the 720 pt panel, else 400).
    func testSelectorStaysInsideTheBlock() throws {
        for lang in ["en", "ru"] {
            for width: CGFloat in [320, 375, 390, 399, 402] {
                let frame = try selectorFrame(lang: lang, width: width)
                XCTAssertGreaterThanOrEqual(frame.minX, inset - 0.5, "\(lang) at \(width) pt: \(frame)")
                XCTAssertLessThanOrEqual(frame.maxX, width - inset + 0.5, "\(lang) at \(width) pt: \(frame)")
            }
        }
    }

    /// Where the row fits, the selector stays beside the title as before.
    func testSelectorBesideTheTitleOnlyWhenTheRowFits() throws {
        for lang in ["en", "ru"] {
            XCTAssertGreaterThan(try selectorFrame(lang: lang, width: 402).minX, inset + 60, lang)
            XCTAssertEqual(try selectorFrame(lang: lang, width: 320).minX, inset, accuracy: 0.5, lang)
        }
    }

    private func selectorFrame(lang: String, width: CGFloat) throws -> CGRect {
        Bundle.setLanguageOverride(lang)
        let recipe = RecipeData(
            id: "nutrition-header",
            name: "Pie",
            servings: 6,
            color: "oklch(0.65 0.25 270)",
            version: "v3",
            description: "",
            ingredients: [],
            nutrition: NutritionData(
                calories: 2400, protein: 40, fat: 120, carbs: 300,
                nutritionOutdated: false, extra: ["totalWeight": 1200]
            ),
            isPublic: false,
            hasSteps: true,
            createdAt: "",
            updatedAt: "",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
        let block = RecipeNutritionBlockView(
            recipe: recipe,
            baseServings: 6,
            scaleFactor: 1,
            accentColor: .orange,
            isOnline: true,
            onRecalculate: nil,
            viewMode: .constant(.dish)
        )
        .environment(\.locale, Locale(identifier: lang))

        let host = UIHostingController(rootView: block)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 400))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.view.layoutIfNeeded()

        let selector = try XCTUnwrap(firstSegmentedControl(in: host.view), "\(lang) at \(width) pt: no selector")
        return selector.convert(selector.bounds, to: host.view)
    }

    private func firstSegmentedControl(in view: UIView) -> UISegmentedControl? {
        if let control = view as? UISegmentedControl { return control }
        for subview in view.subviews {
            if let control = firstSegmentedControl(in: subview) { return control }
        }
        return nil
    }
}
