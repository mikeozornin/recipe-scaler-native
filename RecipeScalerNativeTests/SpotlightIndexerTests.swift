import XCTest
@testable import RecipeScalerNative

final class SpotlightIndexerTests: XCTestCase {
    func testPlainTextCacheReturnsSameResult() {
        let html = "<p>Bring to <strong>boil</strong></p>"
        let first = SpotlightIndexer._testPlainText(fromHTML: html)
        let second = SpotlightIndexer._testPlainText(fromHTML: html)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "Bring to boil")
    }

    func testBuildItemRunsWithoutMainActorDependencies() async {
        let entry = CollectionEntry(
            id: "spotlight-test",
            name: "Soup",
            color: "#3b82f6",
            imageUrl: nil,
            updatedAt: "2026-01-01T00:00:00.000Z",
            deleted: false,
            isPinned: false,
            folderIds: []
        )
        let recipe = RecipeData(
            id: entry.id,
            name: "Soup",
            servings: 2,
            color: "#3b82f6",
            version: "v3",
            description: "<p>Simmer gently</p>",
            ingredients: [
                IngredientData(id: "i1", name: "Carrot", order: 1),
            ],
            nutrition: nil,
            isPublic: false,
            hasSteps: true,
            createdAt: "",
            updatedAt: "",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )

        let item = await Task.detached {
            SpotlightIndexer._testBuildItem(entry: entry, recipe: recipe)
        }.value

        XCTAssertEqual(item?.uniqueIdentifier, entry.id)
        XCTAssertEqual(item?.attributeSet.title, "Soup")
    }
}
