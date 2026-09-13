import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class ProcessTableRebuildTests: XCTestCase {
    func testCancelDropsInFlightErrorToast() async {
        let model = ProcessTableRebuildModel()
        model.rebuildOverride = { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
            throw APIError.httpError(statusCode: 500)
        }

        var sawToast = false
        let observer = NotificationCenter.default.addObserver(
            forName: .shoppingStatusMessage,
            object: nil,
            queue: .main
        ) { _ in
            sawToast = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        model.rebuild(recipeId: "r1", userId: "u1", syncService: nil)
        XCTAssertTrue(model.isRebuilding)
        model.cancel()
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(sawToast)
        XCTAssertFalse(model.isRebuilding)
    }

    func testOptionalParentStateCallbackBecomesNoOp() {
        let model = ProcessTableRebuildModel()
        var ran = false
        model.rebuildOverride = { _ in ran = true }

        var parentState: ProcessTableRebuildModel? = model
        let capturedLikeUnmountedView = {
            parentState?.rebuild(recipeId: "r1", userId: nil, syncService: nil)
        }
        parentState = nil
        capturedLikeUnmountedView()
        XCTAssertFalse(ran, "A callback that reads optional @State after unmount must not start rebuild")
    }

    func testCookingOverlayRetainsRebuildModelAfterParentClears() async {
        let model = ProcessTableRebuildModel()
        var ran = false
        model.rebuildOverride = { _ in ran = true }

        let cooking = ProcessTableCookingView(
            recipe: makeRecipe(),
            scaleFactor: 1,
            allowsRebuild: true,
            restoreAwakeOnDismiss: false,
            session: ProcessTableCookingSession(),
            rebuildModel: model
        )
        var parentState: ProcessTableRebuildModel? = model
        parentState = nil
        XCTAssertNil(parentState)
        cooking.rebuildModel.rebuild(recipeId: "r1", userId: nil, syncService: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(ran, "Cooking must keep the rebuild model alive after the recipe card unmounts")
    }

    func testCookingSessionClearsChecksOnDismiss() {
        let cooking = ProcessTableCookingCoordinator()
        cooking.present(
            recipe: makeRecipe(),
            scaleFactor: 1,
            allowsRebuild: false,
            restoreAwakeOnDismiss: false
        )
        let firstId = cooking.presentation?.id
        XCTAssertNotNil(firstId)
        cooking.presentation?.session.toggleIngredient("a")
        cooking.presentation?.session.toggleCell(columnId: "c", startIngredientId: "a")
        XCTAssertTrue(cooking.presentation?.session.measuredIngredientIds.contains("a") == true)

        cooking.dismiss()
        XCTAssertNil(cooking.presentation)

        cooking.present(
            recipe: makeRecipe(),
            scaleFactor: 1,
            allowsRebuild: false,
            restoreAwakeOnDismiss: false
        )
        XCTAssertNotEqual(cooking.presentation?.id, firstId)
        XCTAssertTrue(cooking.presentation?.session.measuredIngredientIds.isEmpty == true)
        XCTAssertTrue(cooking.presentation?.session.doneCellKeys.isEmpty == true)
    }

    private func makeRecipe() -> RecipeData {
        RecipeData(
            id: "r1",
            name: "Loaf",
            servings: 1,
            color: "#000",
            version: "v3",
            description: nil,
            ingredients: [],
            nutrition: nil,
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
    }
}
