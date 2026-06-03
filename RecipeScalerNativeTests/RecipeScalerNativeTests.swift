import UIKit
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

    func testRecipeCollectionMergeKeepsRecipeColorWhenSetEvenIfCollectionNewer() {
        let recipe = RecipeData(
            id: "r1",
            name: "Cake",
            servings: 4,
            color: "#B51A00",
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
            color: "#3b82f6",
            imageUrl: nil,
            updatedAt: "2026-06-02T12:00:00.000Z",
            deleted: false,
            isPinned: false
        )
        let merged = RecipeCollectionMerge.merged(recipe, with: entry)
        XCTAssertEqual(merged.color, "#B51A00")
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

    func testXmlFragmentHTMLEscapes() {
        XCTAssertEqual(
            XmlFragmentToHTML.escapeHTML("a < b & \"c\""),
            "a &lt; b &amp; &quot;c&quot;"
        )
    }

    func testXmlFragmentConvertsParagraph() {
        let xml = "<paragraph>Mix flour</paragraph><paragraph>Bake</paragraph>"
        let html = XmlFragmentToHTML.html(fromSerializedXML: xml, ingredients: [])
        XCTAssertEqual(html, "<p>Mix flour</p><p>Bake</p>")
    }

    func testDescriptionFixtureParsesAllElements() {
        let doc = RecipeDescriptionParser.parse(RecipeDescriptionFixture.allElementsHTML)
        let ordered = doc.blocks.filter {
            if case .orderedStep = $0 { return true }
            return false
        }
        XCTAssertEqual(ordered.count, 3)
        XCTAssertTrue(doc.blocks.contains { block in
            if case .paragraph(_, let runs) = block {
                return runs.contains { if case .link = $0 { return true }; return false }
            }
            return false
        })
        XCTAssertTrue(doc.blocks.contains { block in
            if case .orderedStep(_, _, let runs) = block {
                return runs.contains { if case .timer = $0 { return true }; return false }
            }
            return false
        })
        XCTAssertTrue(doc.blocks.contains { block in
            if case .orderedStep(_, _, let runs) = block {
                return runs.contains { if case .ingredient = $0 { return true }; return false }
            }
            return false
        })
    }

    func testXmlFragmentHTMLIncludesLinkAndTimerSpans() {
        let xml = """
        <paragraph>See <link href="https://example.com">Example</link></paragraph>
        <paragraph><timer data-duration="600" data-type="minutes" data-value="10">10 minutes</timer></paragraph>
        """
        let html = XmlFragmentToHTML.html(fromSerializedXML: xml, ingredients: []) ?? ""
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
        XCTAssertTrue(html.contains("timer-reference"))
        XCTAssertTrue(html.contains("10 minutes"))
    }

    func testDescriptionParserFindsAnchorLinks() {
        let html = #"<p>Visit <a href="https://recipe-scaler.ru/mcp">recipe-scaler.ru/mcp</a> today.</p>"#
        let doc = RecipeDescriptionParser.parse(html)
        let hasLink = doc.blocks.contains { block in
            guard case .paragraph(_, let runs) = block else { return false }
            return runs.contains { if case .link(let url, _) = $0 { return url.contains("recipe-scaler.ru") }; return false }
        }
        XCTAssertTrue(hasLink)
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

    func testRecipeImageDiskCacheDetectsExistingFile() throws {
        let recipeId = "verify-disk-cache"
        let fileURL = RecipeImageDiskCache.fileURL(recipeId: recipeId, variant: .full)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertNil(RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .full))
        try Data([0x00]).write(to: fileURL)
        XCTAssertEqual(
            RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .full),
            fileURL
        )
    }

    func testRecipeImageDecoderDownsamplesLargeFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-decode-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200))
        let large = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        }
        try XCTUnwrap(large.pngData()).write(to: fileURL)

        let decoded = RecipeImageDecoder.decode(
            fileURL: fileURL,
            maxPixelSize: RecipeImageDecoder.fullMaxPixelSize
        )
        let image = try XCTUnwrap(decoded)
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), CGFloat(RecipeImageDecoder.fullMaxPixelSize) + 1)
    }

    func testRecipeImageDisplayCacheReturnsSameInstance() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-mem-cache-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let img = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        try XCTUnwrap(img.pngData()).write(to: fileURL)

        let first = try XCTUnwrap(RecipeImageDisplayCache.image(fileURL: fileURL, variant: .full))
        let second = try XCTUnwrap(RecipeImageDisplayCache.image(fileURL: fileURL, variant: .full))
        XCTAssertTrue(first === second)
    }

    @MainActor
    func testAPIClientImageDownloadRequestIncludesUserId() {
        APIClient.shared.configure(userId: "verify-user-id")
        let remoteURL = URL(string: "https://example.test/api/recipes/r1/image")!
        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: remoteURL,
            etag: "etag-1",
            lastModified: nil
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-user-id"), "verify-user-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "etag-1")
        APIClient.shared.configure(userId: nil)
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

    func testLocalUpdateEmittedAfterIngredientRename() async throws {
        let userId = "user-local-sync"
        let recipeId = "recipe-local-sync"
        let ingredientId = "ing-1"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("v3"), txn: txn)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Flour")),
                    ("amount", .string("200")),
                    ("order", .int(1)),
                ]),
            ]), txn: txn)
        }

        var syncedRecipeId: String?
        var syncedUpdate: Data?
        await manager.setLocalUpdateHandler { recipeId, update in
            syncedRecipeId = recipeId
            syncedUpdate = update
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

        XCTAssertEqual(syncedRecipeId, recipeId)
        XCTAssertNotNil(syncedUpdate)
        XCTAssertFalse(syncedUpdate?.isEmpty ?? true)

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.ingredients.first?.name, "Whole wheat flour")
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

    func testAddIngredientViaIngredientMapDoesNotCrash() async throws {
        let userId = "user-add-ingredient"
        let recipeId = "recipe-add-ingredient"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "ingredients", value: .yarray([]), txn: txn)
        }

        let ingredient = IngredientData(
            id: "ing-new",
            name: "Мука 🌾",
            amount: "200",
            originalAmount: "200",
            unit: "g",
            order: 1,
            calories: 364,
            protein: 10,
            fat: 1,
            carbs: 76
        )
        try await manager.addIngredient(recipeId: recipeId, ingredient: ingredient)

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.ingredients.count, 1)
        XCTAssertEqual(readBack?.ingredients.first?.name, "Мука 🌾")
        XCTAssertEqual(readBack?.ingredients.first?.calories, 364)
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

    func testRecipeNutritionDisplayPerServingMatchesWeb() {
        let recipe = RecipeData(
            id: "r1",
            name: "Test",
            servings: 3,
            color: "oklch(0.65 0.25 270)",
            version: "3",
            description: nil,
            ingredients: [
                IngredientData(id: "1", name: "A", calories: 300, protein: 10, fat: 5, carbs: 20),
                IngredientData(id: "2", name: "B", calories: 150, protein: 5, fat: 2, carbs: 10),
            ],
            nutrition: NutritionData(calories: 9999, protein: 0, fat: 0, carbs: 0, extra: [:]),
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
        let effective = RecipeNutritionDisplay.effectiveMacros(from: recipe)
        XCTAssertEqual(effective?.calories, 450)

        let perServing = RecipeNutritionDisplay.displayMacros(
            effective: effective!,
            baseServings: 3,
            viewServings: 3,
            recipeServings: 3,
            totalWeight: nil,
            mode: .perServing
        )
        XCTAssertEqual(perServing.calories, 150)
    }

    func testRecipeServingsNormalizeStringAndScaled() {
        XCTAssertEqual(RecipeServings.normalize("10"), 10)
        XCTAssertEqual(RecipeServings.normalize("10,5"), 11)
        XCTAssertEqual(RecipeServings.normalize("0"), nil)
        XCTAssertEqual(RecipeServings.scaledServings(base: 1, scaleFactor: 10), 10)
        XCTAssertEqual(RecipeServings.scaledServings(base: 4, scaleFactor: 2.5), 10)
    }

    func testIngredientNutritionSummaryLineScaledMode() {
        let ingredient = IngredientData(
            id: "1",
            name: "Sugar",
            originalAmount: "200",
            unit: "г",
            calories: 800,
            protein: 8,
            fat: 0,
            carbs: 200,
            weight: 200
        )
        let line = IngredientNutritionDisplay.summaryLine(
            ingredient: ingredient,
            baseServings: 4,
            viewServings: 8,
            mode: .scaled
        )
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("1600") == true)
    }

    func testIngredientNutritionEditingPer100gRoundTrip() {
        let ingredient = IngredientData(
            id: "1",
            name: "Sugar",
            originalAmount: "200",
            unit: "г",
            calories: 800,
            protein: 0,
            fat: 0,
            carbs: 200,
            weight: 200
        )
        let per100g = IngredientNutritionEditing.per100gValues(from: ingredient)
        XCTAssertEqual(per100g.calories, 400)

        let absolute = IngredientNutritionEditing.absoluteValues(
            per100g: IngredientNutritionEditing.Per100gValues(calories: 400, protein: 0, fat: 0, carbs: 100),
            weightGrams: ingredient.resolvedWeightGrams
        )
        XCTAssertEqual(absolute.calories, 800)
        XCTAssertEqual(absolute.carbs, 200)
    }

    func testCollectionPinAndTombstone() async throws {
        let userId = "user-col-mut"
        let recipeId = "recipe-col-mut"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let collectionDoc = try await manager.getOrCreateDoc(key: "\(userId):collection")
        try await collectionDoc.withWriteTransaction { rawDoc, txn in
            guard let arrayBranch = yarray(rawDoc, "recipes") else { return }
            let array = YrsArray(branch: arrayBranch)
            array.insert(
                value: .map([
                    ("id", .string(recipeId)),
                    ("name", .string("Soup")),
                    ("color", .string("#3b82f6")),
                    ("updatedAt", .string("2026-06-01T10:00:00Z")),
                    ("deleted", .bool(false)),
                    ("isPinned", .bool(false)),
                ]),
                at: 0,
                txn: txn
            )
        }

        try await manager.setCollectionEntryPinned(recipeId: recipeId, isPinned: true)
        var entries = try await manager.readCollectionEntries()
        XCTAssertTrue(entries.first { $0.id == recipeId }?.isPinned == true)

        try await manager.tombstoneCollectionEntry(recipeId: recipeId)
        entries = try await manager.readCollectionEntries()
        XCTAssertTrue(entries.first { $0.id == recipeId }?.deleted == true)
    }

    func testCreateRecipeWritesV3DocAndCollectionEntry() async throws {
        let userId = "user-create"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Fresh pasta")

        let entries = try await manager.readCollectionEntries()
        let entry = try XCTUnwrap(entries.first { $0.id == recipeId })
        XCTAssertEqual(entry.name, "Fresh pasta")
        XCTAssertFalse(entry.deleted)

        let recipe = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(recipe?.version, "v3")
        XCTAssertEqual(recipe?.servings, 1)
        XCTAssertEqual(recipe?.ingredients.count, 0)
    }

    func testUpdateRecipeNamePersistsInDocAndCollection() async throws {
        let userId = "user-title-save"
        let store = YDocStore(inMemory: true)
        let manager = DocumentManager(store: store)
        manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Before rename")
        try await manager.updateRecipeName(recipeId: recipeId, name: "After rename")

        let recipe = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(recipe?.name, "After rename")

        let entries = try await manager.readCollectionEntries()
        let entry = try XCTUnwrap(entries.first { $0.id == recipeId })
        XCTAssertEqual(entry.name, "After rename")

        let snapshot = try await store.loadSnapshot(docKey: "\(userId):recipe:\(recipeId)")
        XCTAssertNotNil(snapshot)
        XCTAssertFalse(snapshot?.state.isEmpty ?? true)
    }

    func testAppTabBarSymbolsExistInUIKit() {
        for tab in AppTab.allCases {
            XCTAssertNotNil(
                UIImage(systemName: tab.tabBarSymbol),
                "Missing SF Symbol for tab \(tab.rawValue): \(tab.tabBarSymbol)"
            )
        }
        XCTAssertNotNil(UIImage(systemName: "globe.fill"))
        XCTAssertNil(
            UIImage(systemName: "square.and.arrow.down.fill"),
            "square.and.arrow.down.fill is not a valid SF Symbol — use square.and.arrow.down in tabItem"
        )
    }
}
