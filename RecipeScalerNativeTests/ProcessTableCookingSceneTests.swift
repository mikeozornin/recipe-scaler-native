import SwiftUI
import UIKit
import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

/// Orientation lock and presentation on the live `UIWindowScene`.
@MainActor
final class ProcessTableCookingSceneTests: XCTestCase {
    override func tearDown() {
        ProcessTableCookingPresenter.dismissOverlay()
        super.tearDown()
    }

    func testBeginSessionAdvertisesLandscapeWithoutRotatingUntilAsked() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "Forced landscape is iPhone-only")
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first

        ProcessTableCookingPresenter.unlockOrientation()
        let rest = ProcessTableCookingPresenter.supportedInterfaceOrientations(for: window)
        XCTAssertTrue(
            rest.contains(.portrait),
            "App is portrait-primary while cooking is closed; got \(rest.rawValue)"
        )
        XCTAssertFalse(
            rest.contains(.landscapeLeft) || rest.contains(.landscapeRight),
            "Landscape must not be advertised before cooking is on screen; got \(rest.rawValue)"
        )

        ProcessTableCookingPresenter.beginLandscapeSession(requestGeometry: false)
        let cooking = ProcessTableCookingPresenter.supportedInterfaceOrientations(for: window)
        XCTAssertTrue(
            cooking.contains(.landscapeLeft) && cooking.contains(.landscapeRight),
            "After cooking is visible the app delegate must allow landscape; got \(cooking.rawValue)"
        )
        XCTAssertFalse(
            cooking.contains(.portrait),
            "Portrait must not be advertised while cooking is locked to landscape; got \(cooking.rawValue)"
        )

        ProcessTableCookingPresenter.unlockOrientation()
        let restored = ProcessTableCookingPresenter.supportedInterfaceOrientations(for: window)
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
        ProcessTableCookingPresenter.presentOverlay(makeCookingView())
        pumpMain(seconds: 0.6)

        XCTAssertNotNil(
            ProcessTableCookingCoverModel.shared.item,
            "Start cooking must set the ContentView cooking cover item"
        )
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let root = windows.first(where: \.isKeyWindow)?.rootViewController
            ?? windows.first?.rootViewController
        XCTAssertTrue(
            containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableGrid,
                in: root?.view
            ) || containsAccessibilityIdentifier(
                AccessibilityIdentifiers.recipeProcessTableGrid,
                in: root
            ),
            "Presented cooking cover must show the process-table grid"
        )
        XCTAssertTrue(
            windows.contains { window in
                containsAccessibilityIdentifier(
                    AccessibilityIdentifiers.recipeProcessTableClose,
                    in: window
                ) || containsAccessibilityIdentifier(
                    AccessibilityIdentifiers.recipeProcessTableClose,
                    in: window.rootViewController
                )
            },
            "Close must be reachable in the cooking chrome"
        )
    }

    // MARK: - Fixture

    private func makeCookingView() -> ProcessTableCookingView {
        let ingredients = [
            IngredientData(id: "a", name: "Flour", originalAmount: "200", unit: "g"),
            IngredientData(id: "b", name: "Water", originalAmount: "120", unit: "g"),
        ]
        let html = "<ol><li>Mix</li><li>Bake</li></ol>"
        let hash = ProcessTableSourceHash.hash(ingredients: ingredients, descriptionHtml: html)
        return ProcessTableCookingView(
            recipe: RecipeData(
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
            ),
            scaleFactor: 1,
            allowsRebuild: false,
            restoreAwakeOnDismiss: false,
            rebuildModel: ProcessTableRebuildModel(api: APIClient.shared),
            onStartTimer: { _ in }
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
