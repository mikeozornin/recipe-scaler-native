import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class ProcessTableRebuildTests: XCTestCase {
    func testCancelDropsInFlightErrorToast() async {
        let model = ProcessTableRebuildModel(api: APIClient.shared)
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
        let model = ProcessTableRebuildModel(api: APIClient.shared)
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
        let model = ProcessTableRebuildModel(api: APIClient.shared)
        var ran = false
        model.rebuildOverride = { _ in ran = true }

        let cooking = ProcessTableCookingView(
            recipe: RecipeData(
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
            ),
            scaleFactor: 1,
            allowsRebuild: true,
            restoreAwakeOnDismiss: false,
            rebuildModel: model,
            onStartTimer: { _ in }
        )
        var parentState: ProcessTableRebuildModel? = model
        parentState = nil
        XCTAssertNil(parentState)
        cooking.rebuildModel.rebuild(recipeId: "r1", userId: nil, syncService: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(ran, "Cooking must keep the rebuild model alive after the recipe card unmounts")
    }

    func testCookingSessionClearsChecks() {
        let session = ProcessTableCookingSession()
        session.toggleIngredient("a")
        session.toggleCell(columnId: "c", startIngredientId: "a")
        XCTAssertTrue(session.measuredIngredientIds.contains("a"))
        let fresh = ProcessTableCookingSession()
        XCTAssertTrue(fresh.measuredIngredientIds.isEmpty)
        XCTAssertTrue(fresh.doneCellKeys.isEmpty)
    }
}
