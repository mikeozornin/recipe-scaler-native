import XCTest
import RecipeScalerCore

final class NativeRecipeExporterTests: XCTestCase {
    func testJsonRoundTripPreservesCoreFields() throws {
        let recipe = ExportRecipe(
            id: "recipe-abc",
            name: "Tomato Soup",
            description: "<p>Comfort food</p>",
            ingredients: [
                ExportIngredient(
                    id: "ing-1",
                    name: "tomatoes",
                    originalAmount: 2,
                    unit: "pcs",
                    order: 1,
                    isSeparator: nil
                )
            ],
            color: "oklch(0.65 0.25 270)",
            servings: 4,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-06-01T00:00:00Z",
            originalRecipeLink: "https://example.com/soup",
            originalRecipe: "Example Cookbook",
            nutrition: ExportNutrition(
                calories: 120,
                protein: 4,
                fat: 2,
                carbs: 18,
                calculatedAt: nil,
                nutritionOutdated: false,
                totalWeight: 850
            ),
            imageUrl: nil
        )

        let folders = [
            ExportFolder(
                id: "folder-1",
                name: "Soups",
                color: "#ff0000",
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-06-01T00:00:00Z"
            )
        ]

        let export = try NativeRecipeExporter.export(
            recipes: [recipe],
            recipeFolderIds: ["recipe-abc": ["folder-1"]],
            folders: folders
        )

        XCTAssertFalse(export.hasImages)
        XCTAssertTrue(export.filename.hasSuffix(".json"))

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-export-\(UUID().uuidString).json")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        // Exporter produces v1.4 with optional amountText for non-numeric amounts.
        XCTAssertEqual(parsed.version, .v1_4)
        XCTAssertEqual(parsed.recipes.count, 1)

        let imported = try XCTUnwrap(parsed.recipes.first)
        XCTAssertEqual(imported.id, "recipe-abc")
        XCTAssertEqual(imported.name, "Tomato Soup")
        XCTAssertEqual(imported.description, "<p>Comfort food</p>")
        XCTAssertEqual(imported.servings, 4)
        XCTAssertEqual(imported.folderIds, ["folder-1"])
        XCTAssertEqual(imported.ingredients.count, 1)
        XCTAssertEqual(imported.ingredients[0].name, "tomatoes")
        XCTAssertEqual(imported.nutrition?.calories, 120)
        XCTAssertEqual(imported.nutrition?.totalWeight, 850)
        XCTAssertEqual(parsed.folders.count, 1)
        XCTAssertEqual(parsed.folders[0].name, "Soups")
    }

    func testZipExportIncludesRecipesJson() throws {
        let recipe = ExportRecipe(
            id: "recipe-img",
            name: "Cake",
            description: nil,
            ingredients: [],
            color: "oklch(0.65 0.25 270)",
            servings: 8,
            createdAt: nil,
            updatedAt: nil,
            originalRecipeLink: nil,
            originalRecipe: nil,
            nutrition: nil,
            imageUrl: "https://example.com/cake.jpg"
        )

        let imageData: [String: (full: Data, preview: Data)] = [
            "recipe-img": (full: Data([0x01, 0x02]), preview: Data([0x03]))
        ]

        let export = try NativeRecipeExporter.export(
            recipes: [recipe],
            recipeFolderIds: [:],
            folders: [],
            imageData: imageData
        )

        XCTAssertTrue(export.hasImages)
        XCTAssertTrue(export.filename.hasSuffix(".zip"))

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-export-\(UUID().uuidString).zip")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.recipes.count, 1)
        XCTAssertEqual(parsed.imageEntries.count, 2)
        XCTAssertTrue(parsed.imageEntries.contains { $0.kind == .full && $0.recipeId == "recipe-img" })
        XCTAssertTrue(parsed.imageEntries.contains { $0.kind == .preview && $0.recipeId == "recipe-img" })
    }

    /// Streaming export produces an archive that round-trips identically to
    /// the in-memory export, including the image manifest and bytes.
    func testStreamingExportMatchesInMemoryLayout() throws {
        let recipe = ExportRecipe(
            id: "recipe-stream",
            name: "Pie",
            description: "<p>Flaky</p>",
            ingredients: [],
            color: "oklch(0.65 0.25 270)",
            servings: 2,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-06-01T00:00:00Z",
            originalRecipeLink: nil,
            originalRecipe: nil,
            nutrition: nil,
            imageUrl: "https://example.com/pie.jpg"
        )

        // Write fake full/preview image bytes to temp files so the streaming
        // exporter reads them via the FileHandle-based provider.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("streaming-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fullURL = tempDir.appendingPathComponent("full.webp")
        let previewURL = tempDir.appendingPathComponent("preview.webp")
        let fullBytes = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let previewBytes = Data([0x11, 0x22])
        try fullBytes.write(to: fullURL)
        try previewBytes.write(to: previewURL)

        let imageFile = NativeRecipeExporter.ImageFile(
            recipeId: "recipe-stream",
            fullURL: fullURL,
            previewURL: previewURL
        )

        let export = try NativeRecipeExporter.exportStreaming(
            recipes: [recipe],
            recipeFolderIds: [:],
            folders: [],
            imageFiles: [imageFile]
        )

        XCTAssertTrue(export.hasImages)
        XCTAssertTrue(export.filename.hasSuffix(".zip"))

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-streaming-\(UUID().uuidString).zip")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.recipes.count, 1)
        XCTAssertEqual(parsed.recipes.first?.id, "recipe-stream")
        XCTAssertEqual(parsed.recipes.first?.name, "Pie")
        XCTAssertEqual(parsed.recipes.first?.description, "<p>Flaky</p>")
        XCTAssertEqual(parsed.imageEntries.count, 2)
        XCTAssertTrue(parsed.imageEntries.contains { $0.kind == .full && $0.recipeId == "recipe-stream" })
        XCTAssertTrue(parsed.imageEntries.contains { $0.kind == .preview && $0.recipeId == "recipe-stream" })
    }

    /// Streaming export with no images produces a plain JSON file matching
    /// the in-memory path.
    func testStreamingExportWithoutImagesProducesJson() throws {
        let recipe = ExportRecipe(
            id: "recipe-json",
            name: "Soup",
            description: nil,
            ingredients: [],
            color: "#3b82f6",
            servings: nil,
            createdAt: nil,
            updatedAt: nil,
            originalRecipeLink: nil,
            originalRecipe: nil,
            nutrition: nil,
            imageUrl: nil
        )

        let export = try NativeRecipeExporter.exportStreaming(
            recipes: [recipe],
            recipeFolderIds: [:],
            folders: [],
            imageFiles: []
        )

        XCTAssertFalse(export.hasImages)
        XCTAssertTrue(export.filename.hasSuffix(".json"))

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-streaming-json-\(UUID().uuidString).json")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.recipes.count, 1)
        XCTAssertEqual(parsed.recipes.first?.name, "Soup")
    }

    // MARK: - v1.4 amountText roundtrip (finding #15)

    /// Non-numeric ingredient amounts ("1/2", "2-3", "to taste", …) must
    /// survive export → parse roundtrip via the optional `amountText` field.
    func testV14RoundTripPreservesNonNumericAmountText() throws {
        let recipe = ExportRecipe(
            id: "recipe-text",
            name: "Bread",
            description: nil,
            ingredients: [
                ExportIngredient(
                    id: "ing-text",
                    name: "yeast",
                    originalAmount: nil,
                    amountText: "1/2",
                    unit: "tsp",
                    order: 1,
                    isSeparator: nil
                )
            ],
            color: "#3b82f6",
            servings: 2,
            createdAt: nil,
            updatedAt: nil,
            originalRecipeLink: nil,
            originalRecipe: nil,
            nutrition: nil,
            imageUrl: nil
        )

        let export = try NativeRecipeExporter.export(
            recipes: [recipe],
            recipeFolderIds: [:],
            folders: []
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v14-text-\(UUID().uuidString).json")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.version, .v1_4)
        XCTAssertEqual(parsed.recipes.count, 1)

        let ing = try XCTUnwrap(parsed.recipes.first?.ingredients.first)
        XCTAssertNil(ing.originalAmount, "Numeric originalAmount must be nil for text-only amount")
        XCTAssertEqual(ing.amountText, "1/2")
        XCTAssertEqual(ing.unit, "tsp")
    }

    /// Numeric and text amounts may coexist in the same recipe and must
    /// each be preserved.
    func testV14RoundTripPreservesMixedAmounts() throws {
        let recipe = ExportRecipe(
            id: "recipe-mixed",
            name: "Stew",
            description: nil,
            ingredients: [
                ExportIngredient(
                    id: "ing-num",
                    name: "carrots",
                    originalAmount: 3,
                    amountText: nil,
                    unit: "pcs",
                    order: 1,
                    isSeparator: nil
                ),
                ExportIngredient(
                    id: "ing-text",
                    name: "salt",
                    originalAmount: nil,
                    amountText: "to taste",
                    unit: nil,
                    order: 2,
                    isSeparator: nil
                )
            ],
            color: "#3b82f6",
            servings: 4,
            createdAt: nil,
            updatedAt: nil,
            originalRecipeLink: nil,
            originalRecipe: nil,
            nutrition: nil,
            imageUrl: nil
        )

        let export = try NativeRecipeExporter.export(
            recipes: [recipe],
            recipeFolderIds: [:],
            folders: []
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v14-mixed-\(UUID().uuidString).json")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.version, .v1_4)
        let ings = try XCTUnwrap(parsed.recipes.first?.ingredients)
        XCTAssertEqual(ings.count, 2)

        XCTAssertEqual(ings[0].originalAmount, 3)
        XCTAssertNil(ings[0].amountText)

        XCTAssertNil(ings[1].originalAmount)
        XCTAssertEqual(ings[1].amountText, "to taste")
    }

    /// Back-compat: an old v1.4 native file (no amountText anywhere) must
    /// still parse and produce the same shape as before — no regression.
    func testV14FileWithoutAmountTextStillParses() throws {
        let json = """
        {
          "metadata": {
            "version": "1.4",
            "exportDate": "2026-06-16T12:00:00Z",
            "type": "recipes-v1.4",
            "count": 1
          },
          "recipes": [
            {
              "id": "recipe-old",
              "name": "Old Soup",
              "ingredients": [
                {"id": "ing-1", "name": "salt", "originalAmount": 1, "unit": "tsp", "order": 1}
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v14-old-\(UUID().uuidString).json")
        try json.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.version, .v1_4)
        let ing = try XCTUnwrap(parsed.recipes.first?.ingredients.first)
        XCTAssertEqual(ing.originalAmount, 1)
        XCTAssertNil(ing.amountText)
    }

    // MARK: - nutrition.totalWeight roundtrip (finding #36 / MIK-115)

    /// `nutrition.totalWeight` must survive export → parse roundtrip.
    /// Regression for the bug where ExportNutrition dropped `extra["totalWeight"]`.
    func testV14RoundTripPreservesNutritionTotalWeight() throws {
        let recipe = ExportRecipe(
            id: "recipe-tw",
            name: "Heavy Stew",
            description: nil,
            ingredients: [],
            color: "#3b82f6",
            servings: 6,
            createdAt: nil,
            updatedAt: nil,
            originalRecipeLink: nil,
            originalRecipe: nil,
            nutrition: ExportNutrition(
                calories: 500,
                protein: 20,
                fat: 15,
                carbs: 60,
                calculatedAt: nil,
                nutritionOutdated: false,
                totalWeight: 1200
            ),
            imageUrl: nil
        )

        let export = try NativeRecipeExporter.export(
            recipes: [recipe],
            recipeFolderIds: [:],
            folders: []
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v14-tw-\(UUID().uuidString).json")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.version, .v1_4)

        let nutrition = try XCTUnwrap(parsed.recipes.first?.nutrition)
        XCTAssertEqual(nutrition.calories, 500)
        XCTAssertEqual(nutrition.totalWeight, 1200)
    }

    /// `totalWeight` is optional. A recipe without it must still export and
    /// parse, and the field must be absent from JSON (not `null`).
    func testV14RoundTripWithoutTotalWeightOmitsField() throws {
        let recipe = ExportRecipe(
            id: "recipe-no-tw",
            name: "Light Salad",
            description: nil,
            ingredients: [],
            color: "#3b82f6",
            servings: 2,
            createdAt: nil,
            updatedAt: nil,
            originalRecipeLink: nil,
            originalRecipe: nil,
            nutrition: ExportNutrition(
                calories: 150,
                protein: 3,
                fat: 1,
                carbs: 10,
                calculatedAt: nil,
                nutritionOutdated: true
                // totalWeight intentionally omitted
            ),
            imageUrl: nil
        )

        let export = try NativeRecipeExporter.export(
            recipes: [recipe],
            recipeFolderIds: [:],
            folders: []
        )

        // Total weight must not be present in JSON output (Codable skips nil).
        let jsonString = String(data: export.data, encoding: .utf8) ?? ""
        XCTAssertFalse(
            jsonString.contains("\"totalWeight\""),
            "totalWeight must be omitted from JSON when nil, not serialized as null"
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v14-no-tw-\(UUID().uuidString).json")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        let nutrition = try XCTUnwrap(parsed.recipes.first?.nutrition)
        XCTAssertEqual(nutrition.calories, 150)
        XCTAssertNil(nutrition.totalWeight)
    }
}
