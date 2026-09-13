import SwiftUI
import UIKit
import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

/// Orientation lock and presentation on the live `UIWindowScene`.
@MainActor
final class ProcessTableCookingSceneTests: XCTestCase {
    override func tearDown() {
        AppContainer.shared?.cooking.dismissForLogout()
        super.tearDown()
    }

    func testBeginSessionAdvertisesLandscapeWithoutRotatingUntilAsked() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "Forced landscape is iPhone-only")
        let cooking = ProcessTableCookingCoordinator()
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first

        cooking.unlockOrientation()
        let rest = cooking.supportedInterfaceOrientations(for: window)
        XCTAssertTrue(
            rest.contains(.portrait),
            "App is portrait-primary while cooking is closed; got \(rest.rawValue)"
        )
        XCTAssertFalse(
            rest.contains(.landscapeLeft) || rest.contains(.landscapeRight),
            "Landscape must not be advertised before cooking is on screen; got \(rest.rawValue)"
        )

        cooking.beginLandscapeSession(requestGeometry: false)
        let cookingMask = cooking.supportedInterfaceOrientations(for: window)
        XCTAssertTrue(
            cookingMask.contains(.landscapeLeft) && cookingMask.contains(.landscapeRight),
            "After cooking is visible the app delegate must allow landscape; got \(cookingMask.rawValue)"
        )
        XCTAssertFalse(
            cookingMask.contains(.portrait),
            "Portrait must not be advertised while cooking is locked to landscape; got \(cookingMask.rawValue)"
        )

        cooking.unlockOrientation()
        let restored = cooking.supportedInterfaceOrientations(for: window)
        XCTAssertEqual(restored, rest)
    }

    func testCookingHostingControllerDeclaresLandscape() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "Forced landscape is iPhone-only")
        let host = ProcessTableCookingHostingController(rootView: makeCookingView())
        _ = host.view
        let mask = host.supportedInterfaceOrientations
        XCTAssertTrue(
            mask.contains(.landscapeLeft) && mask.contains(.landscapeRight),
            "Cooking host must declare landscape; got \(mask.rawValue)"
        )
        XCTAssertFalse(
            mask.contains(.portrait),
            "Cooking host must lock landscape until Close; got \(mask.rawValue)"
        )
    }

    func testPresentOverlayFillsScreenAndShowsGrid() throws {
        try XCTSkipIf(
            UIApplication.shared.connectedScenes.isEmpty,
            "Needs a live window scene"
        )
        let cooking = ProcessTableCookingCoordinator()
        let rebuild = ProcessTableRebuildModel()
        cooking.present(
            recipe: makeRecipe(),
            scaleFactor: 1,
            allowsRebuild: false,
            restoreAwakeOnDismiss: false
        )
        let host = UIHostingController(
            rootView: ProcessTableCookingRoot(cooking: cooking, rebuildModel: rebuild) {
                Color.red
            }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 852, height: 393))
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        pumpMain(seconds: 0.6)
        host.view.layoutIfNeeded()

        XCTAssertNotNil(
            cooking.presentation,
            "Start cooking must set the cooking presentation"
        )
        XCTAssertTrue(
            containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableGrid,
                in: host.view
            ) || containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableGrid,
                in: host
            ),
            "Presented cooking cover must show the process-table grid"
        )
        XCTAssertTrue(
            containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableClose,
                in: host.view
            ) || containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableClose,
                in: host
            ),
            "Close must be reachable in the cooking chrome"
        )
    }

    // MARK: - Fixture

    private func makeCookingView() -> ProcessTableCookingView {
        ProcessTableCookingView(
            recipe: makeRecipe(),
            scaleFactor: 1,
            allowsRebuild: false,
            restoreAwakeOnDismiss: false,
            session: ProcessTableCookingSession(),
            rebuildModel: ProcessTableRebuildModel()
        )
    }

    private func makeRecipe() -> RecipeData {
        let ingredients = [
            IngredientData(id: "a", name: "Flour", originalAmount: "200", unit: "g"),
            IngredientData(id: "b", name: "Water", originalAmount: "120", unit: "g"),
        ]
        let html = "<ol><li>Mix</li><li>Bake</li></ol>"
        let hash = ProcessTableSourceHash.hash(ingredients: ingredients, descriptionHtml: html)
        return RecipeData(
            id: "scene-test",
            name: "Scene loaf",
            servings: 1,
            color: "#3b82f6",
            version: "v3",
            description: html,
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
            {"version":1,"sourceHash":"\(hash)","columns":[{"id":"c1","title":"Mix","kind":"cook","stepIndex":0},{"id":"c2","title":"Bake","kind":"cook","stepIndex":1}],"assignments":[{"ingredientId":"a","columnId":"c1"},{"ingredientId":"b","columnId":"c2"}]}
            """
        )
    }

    private func pumpMain(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func containsAccessibilityIdentifier(_ id: String, in view: UIView?) -> Bool {
        guard let view else { return false }
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

    private func containsAccessibilityIdentifier(_ id: String, in controller: UIViewController?) -> Bool {
        guard let controller else { return false }
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
