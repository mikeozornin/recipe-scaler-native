import XCTest
@testable import RecipeScalerNative

final class RecipeSearchUtilsTests: XCTestCase {
    func testTokenizeQuerySupportsQuotedPhrase() {
        let tokens = RecipeSearchUtils.tokenizeQuery(#""beef broth" soup"#)
        XCTAssertEqual(tokens, ["beef broth", "soup"])
    }

    func testNormalizeStripsDiacriticsAndLowercases() {
        XCTAssertEqual(RecipeSearchUtils.normalizeForSearch("Château"), "chateau")
        XCTAssertEqual(RecipeSearchUtils.normalizeForSearch("ГОвяжий"), "говяжий")
    }

    func testMatchesNameIsCaseAndDiacriticInsensitive() {
        let tokens = RecipeSearchUtils.tokenizeQuery("Бул")
        XCTAssertTrue(RecipeSearchUtils.matchesName("Говяжий бульон", tokens: tokens))
    }

    func testMatchesIngredientInRecipe() {
        let recipe = RecipeData(
            id: "1",
            name: "Soup",
            servings: 4,
            color: "oklch(0.65 0.25 270)",
            version: "v3",
            description: "<p>Bring to boil</p>",
            ingredients: [
                IngredientData(id: "i1", name: "Говядина", order: 1),
                IngredientData(id: "i2", name: "Морковь", order: 2),
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

        let tokens = RecipeSearchUtils.tokenizeQuery("говяд")
        XCTAssertFalse(RecipeSearchUtils.matchesName(recipe.name, tokens: tokens))
        XCTAssertTrue(RecipeSearchUtils.matchesRecipeContent(recipe, tokens: tokens))
    }

    func testMatchesDescriptionPlainText() {
        let recipe = RecipeData(
            id: "2",
            name: "Title",
            servings: 1,
            color: "oklch(0.65 0.25 270)",
            version: "v3",
            description: "<p>Добавить <strong>бульон</strong> и варить</p>",
            ingredients: [],
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

        let tokens = RecipeSearchUtils.tokenizeQuery("бульон")
        XCTAssertTrue(RecipeSearchUtils.matchesRecipeContent(recipe, tokens: tokens))
    }

    func testSnippetReturnsIngredientNameAndAmount() {
        let recipe = RecipeData(
            id: "3",
            name: "Soup",
            servings: 4,
            color: "oklch(0.65 0.25 270)",
            version: "v3",
            description: "<p>Steps</p>",
            ingredients: [
                IngredientData(id: "i1", name: "Говядина", originalAmount: "500 г", order: 1),
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

        let tokens = RecipeSearchUtils.tokenizeQuery("говяд")
        let snippet = RecipeSearchUtils.snippet(for: recipe, tokens: tokens, matchesNameOnly: false)
        XCTAssertEqual(snippet, "Говядина, 500 г")
    }

    func testHighlightedAttributedStringMarksMatch() {
        let attributed = RecipeSearchUtils.highlightedAttributedString(
            "Говяжий бульон",
            tokens: RecipeSearchUtils.tokenizeQuery("бул")
        )
        let ns = NSAttributedString(attributed)
        var highlightCount = 0
        ns.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: ns.length)) { value, _, _ in
            if value != nil { highlightCount += 1 }
        }
        XCTAssertGreaterThan(highlightCount, 0)
    }

    func testHighlightedAttributedStringHandlesDiacritics() {
        let attributed = RecipeSearchUtils.highlightedAttributedString(
            "Château Margaux",
            tokens: RecipeSearchUtils.tokenizeQuery("chateau")
        )
        let ns = NSAttributedString(attributed)
        var highlightCount = 0
        ns.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: ns.length)) { value, _, _ in
            if value != nil { highlightCount += 1 }
        }
        XCTAssertGreaterThan(highlightCount, 0)
    }
}
