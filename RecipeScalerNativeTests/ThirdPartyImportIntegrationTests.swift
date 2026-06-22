import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

final class ThirdPartyImportIntegrationTests: XCTestCase {
    /// T021: applyImportedRecipe must produce a recipe that DocumentManager
    /// can read back with the same name and ingredient count.
    ///
    /// History: was `XCTSkipIf(true)`'d because the test host used to perform
    /// live Yjs sync on launch (debug auto-login + Spotlight reindex), stalling
    /// the bundle. The launch-time sync is now gated by
    /// `XCTestConfigurationFilePath` in `AppContainer.bootstrap` (and
    /// `AuthService.init`), so the skip is no longer needed. The test itself
    /// uses an isolated in-memory DocumentManager.
    func testApplyImportedRecipeRoundTripsViaReader() async throws {
        let userId = "user-import-integration"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let draft = ThirdPartyRecipeDraft(
            name: "Integration Cookies",
            servings: 12,
            ingredients: [
                IngredientDraft(name: "Flour", amount: "200 g", order: 1),
                IngredientDraft(name: "Sugar", amount: "100 g", order: 2),
                IngredientDraft(name: "Butter", amount: "150 g", order: 3)
            ],
            descriptionBlocks: [
                .orderedListItem("Mix dry ingredients"),
                .orderedListItem("Bake at 180C")
            ],
            sourceFileName: "integration.crumb",
            sourceFormat: .croutonSingle
        )

        let recipeId = try await manager.applyImportedRecipe(draft)
        XCTAssertFalse(recipeId.isEmpty)

        let recipe = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(recipe?.name, "Integration Cookies")
        XCTAssertEqual(recipe?.ingredients.count, 3)
        XCTAssertEqual(recipe?.servings, 12)
    }

    /// Description blocks survive the round-trip as an ordered list.
    func testApplyImportedRecipeWritesDescriptionBlocks() async throws {
        let userId = "user-import-desc"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let draft = ThirdPartyRecipeDraft(
            name: "Step Salad",
            servings: 4,
            ingredients: [
                IngredientDraft(name: "Lettuce", amount: "1 head", order: 1)
            ],
            descriptionBlocks: [
                .orderedListItem("Wash leaves"),
                .orderedListItem("Toss with dressing")
            ],
            sourceFileName: "salad.crumb",
            sourceFormat: .croutonSingle
        )

        let recipeId = try await manager.applyImportedRecipe(draft)
        let recipe = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        let description = recipe?.description ?? ""
        XCTAssertTrue(description.contains("<ol>"),
                      "Expected <ol> in description, got: \(description)")
    }

    // MARK: - MIK-119 [review #35]: combined photo warnings

    /// When multiple photo buckets are non-zero, `photoWarningMessage` must
    /// surface ALL of them (joined with newlines), not just the first one.
    func testMIK119_PhotoWarningCombinesAllBuckets() {
        let result = ThirdPartyImportResult(
            importedRecipeIds: ["a", "b"],
            failed: [],
            photosSkippedOffline: 1,
            photosFailed: 2,
            photosOversized: 3
        )

        let message = ThirdPartyImportErrorLocalizer.photoWarningMessage(for: result)
        guard let message else {
            return XCTFail("Expected a non-nil combined warning")
        }

        XCTAssertTrue(message.contains("3"), "oversized count should appear; got: \(message)")
        XCTAssertTrue(message.contains("1"), "offline count should appear; got: \(message)")
        XCTAssertTrue(message.contains("2"), "failed count should appear; got: \(message)")
        XCTAssertEqual(message.components(separatedBy: "\n").count, 3,
                       "expected exactly 3 lines, one per bucket; got: \(message)")
    }

    /// Oversized-only result produces a single-line warning.
    func testMIK119_PhotoWarningOversizedOnly() {
        let result = ThirdPartyImportResult(
            importedRecipeIds: ["a"],
            failed: [],
            photosOversized: 5
        )
        let message = ThirdPartyImportErrorLocalizer.photoWarningMessage(for: result)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("5") == true)
        XCTAssertEqual(message?.components(separatedBy: "\n").count, 1)
    }

    /// When all photo counters are zero, no warning should be returned.
    func testMIK119_PhotoWarningNilWhenNothingDropped() {
        let result = ThirdPartyImportResult(
            importedRecipeIds: ["a", "b"],
            failed: [],
            photosSkippedOffline: 0,
            photosFailed: 0,
            photosOversized: 0
        )
        XCTAssertNil(ThirdPartyImportErrorLocalizer.photoWarningMessage(for: result))
    }
}
