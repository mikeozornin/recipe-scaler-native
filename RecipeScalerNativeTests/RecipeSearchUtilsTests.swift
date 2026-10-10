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

    /// NFKD, not NFD: ligatures and full-width forms fold to plain letters.
    func testNormalizeFoldsCompatibilityCharacters() {
        XCTAssertEqual(RecipeSearchUtils.normalizeForSearch("ﬁlet"), "filet")
        XCTAssertEqual(RecipeSearchUtils.normalizeForSearch("Ｐａｓｔａ"), "pasta")
        XCTAssertTrue(RecipeSearchUtils.matchesName("Soufflé ﬁlet", tokens: RecipeSearchUtils.tokenizeQuery("souffle filet")))
        XCTAssertEqual(RecipeSearchUtils.normalizeForSearch("Йогурт"), "йогурт", "Cyrillic й must survive")
    }

    /// Pasted text can carry a decomposed й (и + U+0306); the query has the precomposed one.
    func testDecomposedCyrillicInContentMatchesPrecomposedQuery() {
        let index = RecipeSearchIndex(
            id: "r",
            ingredientNames: ["И\u{0306}огурт"],
            ingredientAmounts: ["200 г"],
            descriptionPlainText: "Добавить и\u{0306}огурт и перемешать"
        )
        let tokens = RecipeSearchUtils.tokenizeQuery("йогурт перемешать")
        XCTAssertNotNil(RecipeSearchUtils.findDescriptionMatch(in: index, tokens: tokens))
        XCTAssertEqual(RecipeSearchUtils.findIngredientMatch(in: index, tokens: ["йогурт"])?.amount, "200 г")
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

@MainActor
final class RecipeListSearchStoreTests: XCTestCase {
    private func entry(id: String, name: String) -> CollectionEntry {
        CollectionEntry(
            id: id,
            name: name,
            color: "",
            imageUrl: nil,
            updatedAt: "",
            deleted: false,
            isPinned: false
        )
    }

    /// The normalized-name cache outlives queries; a rename must not leave
    /// the recipe searchable only by its old name.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<150 where !condition() {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The loaded content index outlives queries; an ingredient edit must not
    /// leave the recipe searchable only by its old content. The entry itself is
    /// unchanged: remote and editor updates do not touch the collection entry.
    func testEditedIngredientIsSearchedByNewContent() async throws {
        let sync = YjsSyncService.makeForTesting(store: try YDocStore.inMemory())
        await sync.test_setUserIdForOfflineTests("u-search")
        let recipeId = try await sync.createRecipe()
        await sync.loadRecipe(recipeId: recipeId)
        try await sync.addIngredient(IngredientData(id: "i1", name: "Морковь", order: 1))

        let entries = [entry(id: recipeId, name: "Суп")]
        let store = RecipeListSearchStore()
        store.bind(syncService: sync)
        store.refresh(entries: entries, query: "морковь")
        await waitUntil { store.filteredSnapshot.map(\.id) == [recipeId] }
        XCTAssertEqual(store.filteredSnapshot.map(\.id), [recipeId])

        try await sync.updateIngredient(IngredientData(id: "i1", name: "Свёкла", order: 1))
        store.refresh(entries: entries, query: "свёкла")
        await waitUntil { store.filteredSnapshot.map(\.id) == [recipeId] }
        XCTAssertEqual(store.filteredSnapshot.map(\.id), [recipeId], "found by the new ingredient")

        store.refresh(entries: entries, query: "морковь")
        XCTAssertEqual(store.filteredSnapshot.map(\.id), [], "no longer found by the old ingredient")
    }

    func testRenamedRecipeIsSearchedByNewName() {
        let store = RecipeListSearchStore()
        store.refresh(entries: [entry(id: "r1", name: "Борщ")], query: "борщ")
        XCTAssertEqual(store.filteredSnapshot.map(\.id), ["r1"])

        let renamed = [entry(id: "r1", name: "Солянка")]
        store.refresh(entries: renamed, query: "солянка")
        XCTAssertEqual(store.filteredSnapshot.map(\.id), ["r1"])

        store.refresh(entries: renamed, query: "борщ")
        XCTAssertTrue(store.filteredSnapshot.isEmpty)
    }
}

/// Highlight ranges must map back correctly when the text contains characters
/// outside the BMP (emoji take two UTF-16 units but one normalized scalar).
final class RecipeSearchHighlightUnicodeTests: XCTestCase {
    private func highlighted(_ text: String, _ query: String) -> [String] {
        let attributed = RecipeSearchUtils.highlightedAttributedString(
            text,
            tokens: RecipeSearchUtils.tokenizeQuery(query)
        )
        let ns = NSAttributedString(attributed)
        var result: [String] = []
        ns.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
            if value != nil { result.append(ns.attributedSubstring(from: range).string) }
        }
        return result
    }

    func testHighlightAfterEmojiIsNotShifted() {
        XCTAssertEqual(highlighted("🍕 pasta", "pasta"), ["pasta"])
    }

    func testHighlightMatchAtEndAfterEmojiDoesNotCrash() {
        XCTAssertEqual(highlighted("Pizza 🍕 Margherita", "a"), ["a", "a", "a"])
        XCTAssertEqual(highlighted("Готово 🎉🎉 ура", "а"), ["а"])
    }

    func testDescriptionSnippetAfterManyEmojiContainsMatch() {
        let text = String(repeating: "🍕 ", count: 200) + "секретный ингредиент" + String(repeating: " слово", count: 100)
        let index = RecipeSearchIndex(id: "r", ingredientNames: [], ingredientAmounts: [], descriptionPlainText: text)
        let tokens = RecipeSearchUtils.tokenizeQuery("секретный")
        let snippet = RecipeSearchUtils.snippet(for: index, tokens: tokens, matchesNameOnly: false)
        XCTAssertTrue(snippet?.contains("секретный") == true, snippet ?? "nil")
    }
}

/// Content matching runs on the main actor for every loaded index on every
/// keystroke, so the per-index cost must not include re-normalizing the text.
final class RecipeSearchContentMatchCostTests: XCTestCase {
    func testMatchingThreeHundredLoadedIndexesStaysUnderAFrameBudgetPerKeystroke() {
        let paragraph = "Обжарить лук до золотистого цвета, добавить crème fraîche и томить 10 минут. "
        let indexes = (0..<300).map { number in
            RecipeSearchIndex(
                id: "r\(number)",
                ingredientNames: (0..<12).map { "Ингредиент \(number)-\($0) Château" },
                ingredientAmounts: Array(repeating: "100 г", count: 12),
                descriptionPlainText: String(repeating: paragraph, count: 26)
            )
        }
        let keystrokes = ["ш", "шп", "шпи", "шпин", "шпина"].map(RecipeSearchUtils.tokenizeQuery)

        let started = Date()
        var matches = 0
        for tokens in keystrokes {
            matches += indexes.filter { RecipeSearchUtils.matchesRecipeContent($0, tokens: tokens) }.count
        }
        let perKeystrokeMs = Date().timeIntervalSince(started) * 1000 / Double(keystrokes.count)
        print("content match: \(String(format: "%.1f", perKeystrokeMs)) ms per keystroke over 300 indexes")

        XCTAssertEqual(matches, 0, "every index is a miss, so each one is fully scanned")
        XCTAssertLessThan(perKeystrokeMs, 16, "one frame at 60 Hz")
    }
}


