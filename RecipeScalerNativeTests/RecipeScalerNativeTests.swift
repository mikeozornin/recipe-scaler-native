import XCTest
@testable import RecipeScalerNative

final class RecipeScalerNativeTests: XCTestCase {
    func testRecipeHasSteps() {
        let recipe = Recipe(name: "Toast", recipeDescription: "Spread and toast")
        XCTAssertTrue(recipe.hasSteps)
    }

    func testRecipeEditPolicyV3Only() {
        XCTAssertTrue(RecipeEditPolicy.canEdit(version: "3"))
        XCTAssertFalse(RecipeEditPolicy.canEdit(version: "1"))
        XCTAssertFalse(RecipeEditPolicy.canEdit(version: "2"))
        XCTAssertFalse(RecipeEditPolicy.canEdit(version: nil))
    }

    func testIngredientAmountLikeBasqueCheesecake() {
        let sugar = IngredientData(
            id: "1",
            name: "Сахар",
            originalAmount: "350",
            unit: "г",
            order: 1
        )
        XCTAssertEqual(sugar.quantityText, "350")
        XCTAssertEqual(sugar.scaledDisplay(targetServings: 8, baseServings: 4), "700")

        let header = IngredientData(
            id: "h",
            name: "Начинка",
            hasQuantity: false
        )
        XCTAssertTrue(header.isHeaderRow)
        XCTAssertEqual(header.scaledDisplay(targetServings: 4, baseServings: 4), "")
    }

    func testRecipeTitleEmojiLeading() {
        XCTAssertEqual(RecipeTitleEmoji.leadingEmoji(in: "🍕 Pizza"), "🍕")
        XCTAssertEqual(RecipeTitleEmoji.leadingEmoji(in: "  🍕 Pizza"), "🍕")
        XCTAssertEqual(RecipeTitleEmoji.leadingEmoji(in: "👨‍👩‍👧 Family"), "👨‍👩‍👧")
        XCTAssertNil(RecipeTitleEmoji.leadingEmoji(in: "Cake 🍰"))
    }

    func testRecipeTitleEmojiDisplayName() {
        XCTAssertEqual(RecipeTitleEmoji.titleWithoutLeadingEmoji("🍕  Pizza"), "Pizza")
        XCTAssertEqual(RecipeTitleEmoji.titleWithoutLeadingEmoji("  🍕 Pizza"), "Pizza")
        XCTAssertEqual(RecipeTitleEmoji.titleWithoutLeadingEmoji("Cake 🍰"), "Cake 🍰")
        XCTAssertEqual(RecipeTitleEmoji.titleWithoutLeadingEmoji("🍕"), "")
    }

    func testRecipeCollectionMergeUsesCollectionColorWhenNewer() {
        let recipe = RecipeData(
            id: "r1",
            name: "Cake",
            servings: 4,
            color: "#111111",
            version: "3",
            description: nil,
            ingredients: [],
            nutrition: nil,
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "2026-06-01T10:00:00.000Z",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
        let entry = CollectionEntry(
            id: "r1",
            name: "Cake",
            color: "#AABBCC",
            imageUrl: nil,
            updatedAt: "2026-06-02T12:00:00.000Z",
            deleted: false,
            isPinned: false
        )
        let merged = RecipeCollectionMerge.merged(recipe, with: entry)
        XCTAssertEqual(merged.color, "#AABBCC")
    }

    func testRecipeCollectionMergeUsesRecipeColorWhenRecipeNewer() {
        let recipe = RecipeData(
            id: "r1",
            name: "Cake",
            servings: 4,
            color: "#111111",
            version: "3",
            description: nil,
            ingredients: [],
            nutrition: nil,
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "2026-06-03T12:00:00.000Z",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
        let entry = CollectionEntry(
            id: "r1",
            name: "Cake",
            color: "#AABBCC",
            imageUrl: nil,
            updatedAt: "2026-06-01T10:00:00.000Z",
            deleted: false,
            isPinned: false
        )
        let merged = RecipeCollectionMerge.merged(recipe, with: entry)
        XCTAssertEqual(merged.color, "#111111")
    }

    func testRecipeCollectionMergeUsesCollectionWhenRecipeColorEmpty() {
        let recipe = RecipeData(
            id: "r1",
            name: "Cake",
            servings: 4,
            color: "   ",
            version: "3",
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
        let entry = CollectionEntry(
            id: "r1",
            name: "Cake",
            color: "oklch(0.7 0.2 120)",
            imageUrl: nil,
            updatedAt: "",
            deleted: false,
            isPinned: false
        )
        let merged = RecipeCollectionMerge.merged(recipe, with: entry)
        XCTAssertEqual(merged.color, "oklch(0.7 0.2 120)")
    }

    func testRecipeImageVersionToken() {
        XCTAssertEqual(
            RecipeImageVersion.token(from: "user/recipe-id/full/abc123.webp"),
            "abc123"
        )
        XCTAssertNil(RecipeImageVersion.token(from: nil))
        XCTAssertNil(RecipeImageVersion.token(from: ""))
    }

    func testPrefetchPreviewsRemovesCacheWhenImageUrlEmpty() async {
        let recipeId = "recipe-no-image"
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let previewURL = cachesDir
            .appendingPathComponent("RecipeImages", isDirectory: true)
            .appendingPathComponent("\(recipeId)_preview.webp")

        try? FileManager.default.createDirectory(
            at: previewURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data([0xFF]).write(to: previewURL)

        let entry = CollectionEntry(
            id: recipeId,
            name: "Test",
            color: "oklch(0.65 0.25 270)",
            imageUrl: nil,
            updatedAt: "",
            deleted: false,
            isPinned: false
        )

        await RecipeImageService.shared.prefetchPreviews(entries: [entry], allowNetwork: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: previewURL.path))
        let cached = await RecipeImageService.shared.localFileURL(recipeId: recipeId, variant: .preview)
        XCTAssertNil(cached)
    }

    func testRecipeTitleEmojiSortOrder() {
        let input = ["🍕 Pizza", "Apple Pie", "☕ Coffee"]
        let sorted = input.sorted { lhs, rhs in
            RecipeTitleEmoji.compareNames(lhs, rhs) == .orderedAscending
        }
        XCTAssertEqual(sorted, ["Apple Pie", "☕ Coffee", "🍕 Pizza"])
    }

    func testRapidIngredientUpdatesDoNotCrash() async throws {
        let userId = "user-rapid"
        let recipeId = "recipe-rapid"
        let ingredientId = "ing-rapid"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Flour")),
                    ("amount", .string("200")),
                    ("order", .int(1)),
                ]),
            ]), txn: txn)
        }

        for index in 0..<50 {
            let ingredient = IngredientData(
                id: ingredientId,
                name: "Name \(index)",
                amount: "200",
                originalAmount: "200",
                unit: "",
                order: 1
            )
            try await manager.updateIngredient(recipeId: recipeId, ingredient: ingredient)
            _ = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        }
    }

    func testUpdateIngredientRenameDoesNotCrash() async throws {
        let userId = "user-ingredient-rename"
        let recipeId = "recipe-ingredient-rename"
        let ingredientId = "ing-1"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Flour")),
                    ("amount", .string("200")),
                    ("order", .int(1)),
                ]),
            ]), txn: txn)
        }

        let renamed = IngredientData(
            id: ingredientId,
            name: "Whole wheat flour",
            amount: "200",
            originalAmount: "200",
            unit: "",
            order: 1
        )
        try await manager.updateIngredient(recipeId: recipeId, ingredient: renamed)

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.ingredients.first?.name, "Whole wheat flour")
    }

    func testUpdateRecipeColorThenSortCollectionDoesNotCrash() async throws {
        let userId = "user-color-sort"
        let recipeId = "recipe-color-sort"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let collectionDoc = try await manager.getOrCreateDoc(key: "\(userId):collection")
        try await collectionDoc.withWriteTransaction { _, txn in
            guard let arrayBranch = ytype_get(txn, "recipes") else { return }
            let array = YrsArray(branch: arrayBranch)
            array.insert(
                value: .map([
                    ("id", .string(recipeId)),
                    ("name", .string("🍕 Pizza")),
                    ("color", .string("oklch(0.65 0.25 270)")),
                    ("updatedAt", .string("2026-06-01T10:00:00Z")),
                ]),
                at: 0,
                txn: txn
            )
        }

        let recipeDoc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await recipeDoc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "color", value: .string("oklch(0.65 0.25 270)"), txn: txn)
        }

        try await manager.updateRecipeColor(recipeId: recipeId, color: "#FF5500")

        let entries = try await manager.readCollectionEntries()
        let sorted = RecipeTitleEmoji.sortCollectionEntries(entries)
        XCTAssertEqual(sorted.first?.color, "#FF5500")
        XCTAssertEqual(RecipeTitleEmoji.leadingEmoji(in: sorted.first?.name), "🍕")
    }

    func testUpdateRecipeColorDoesNotCrash() async throws {
        let userId = "user-color"
        let recipeId = "recipe-color"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "color", value: .string("oklch(0.65 0.25 270)"), txn: txn)
        }

        try await manager.updateRecipeColor(recipeId: recipeId, color: "#AABBCC")

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.color, "#AABBCC")
    }

    func testUpdateNutritionDoesNotCrash() async throws {
        let userId = "user-nutrition"
        let recipeId = "recipe-nutrition"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "nutrition", value: .map([
                ("calories", .double(100)),
                ("protein", .double(10)),
            ]), txn: txn)
        }

        try await manager.updateNutrition(
            recipeId: recipeId,
            calories: 250,
            protein: 20,
            fat: 8,
            carbs: 30
        )

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.nutrition?.calories, 250)
        XCTAssertEqual(readBack?.nutrition?.protein, 20)
        XCTAssertEqual(readBack?.nutrition?.fat, 8)
        XCTAssertEqual(readBack?.nutrition?.carbs, 30)
    }

    func testIngredientNutritionAggregation() {
        let a = IngredientData(
            id: "1",
            name: "Sugar",
            calories: 100,
            protein: 0,
            fat: 0,
            carbs: 25
        )
        let b = IngredientData(
            id: "2",
            name: "Butter",
            calories: 200,
            protein: 1,
            fat: 22,
            carbs: 0
        )
        let totals = IngredientData.aggregatedMacros(from: [a, b])
        XCTAssertEqual(totals?.calories, 300)
        XCTAssertEqual(totals?.protein, 1)
        XCTAssertEqual(totals?.fat, 22)
        XCTAssertEqual(totals?.carbs, 25)
    }
}
