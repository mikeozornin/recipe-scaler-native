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
                nutritionOutdated: false
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
        // Exporter now produces v1.5 (introduces the amountText field for
        // non-numeric amounts — finding #15).
        XCTAssertEqual(parsed.version, .v1_5)
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

    // MARK: - v1.5 amountText roundtrip (finding #15)

    /// Non-numeric ingredient amounts ("1/2", "2-3", "to taste", …) must
    /// survive export → parse roundtrip via the new `amountText` field.
    func testV15RoundTripPreservesNonNumericAmountText() throws {
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
            .appendingPathComponent("v15-text-\(UUID().uuidString).json")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.version, .v1_5)
        XCTAssertEqual(parsed.recipes.count, 1)

        let ing = try XCTUnwrap(parsed.recipes.first?.ingredients.first)
        XCTAssertNil(ing.originalAmount, "Numeric originalAmount must be nil for text-only amount")
        XCTAssertEqual(ing.amountText, "1/2")
        XCTAssertEqual(ing.unit, "tsp")
    }

    /// Numeric and text amounts may coexist in the same recipe and must
    /// each be preserved.
    func testV15RoundTripPreservesMixedAmounts() throws {
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
            .appendingPathComponent("v15-mixed-\(UUID().uuidString).json")
        try export.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parsed = try NativeRecipeImporter.parse(url: tempURL)
        XCTAssertEqual(parsed.version, .v1_5)
        let ings = try XCTUnwrap(parsed.recipes.first?.ingredients)
        XCTAssertEqual(ings.count, 2)

        XCTAssertEqual(ings[0].originalAmount, 3)
        XCTAssertNil(ings[0].amountText)

        XCTAssertNil(ings[1].originalAmount)
        XCTAssertEqual(ings[1].amountText, "to taste")
    }

    /// Back-compat: a web v1.4 file may emit `originalAmount` as a raw JSON
    /// string (web dumps ingredients as-is). The polymorphic decoder must
    /// route it into `amountText` without throwing.
    func testWebV14StringOriginalAmountParsesAsAmountText() throws {
        let json = """
        {
          "metadata": {
            "version": "1.4",
            "exportDate": "2026-06-18T12:00:00Z",
            "type": "recipes-v1.4",
            "count": 1
          },
          "recipes": [
            {
              "id": "web-recipe",
              "name": "Web Soup",
              "ingredients": [
                {
                  "id": "web-ing",
                  "name": "salt",
                  "originalAmount": "to taste",
                  "unit": null,
                  "order": 1
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(NativeExportPayload.self, from: json)
        XCTAssertEqual(payload.recipes.count, 1)
        let ing = try XCTUnwrap(payload.recipes.first?.ingredients.first)
        XCTAssertNil(ing.originalAmount, "String originalAmount must NOT land in the Double field")
        XCTAssertEqual(ing.amountText, "to taste", "String originalAmount must be routed to amountText")
    }

    /// Polymorphic `originalAmount` decoder must handle all four input
    /// shapes: missing key, null, number, string.
    func testPolymorphicOriginalAmountAcceptsAllShapes() throws {
        let json = """
        {
          "metadata": {"version": "1.5", "exportDate": "2026-06-18T12:00:00Z", "type": "recipes-v1.5", "count": 4},
          "recipes": [
            {"id": "r1", "name": "Missing", "ingredients": [
              {"id": "i1", "name": "x", "unit": null, "order": 1}
            ]},
            {"id": "r2", "name": "Null", "ingredients": [
              {"id": "i2", "name": "x", "originalAmount": null, "unit": null, "order": 1}
            ]},
            {"id": "r3", "name": "Number", "ingredients": [
              {"id": "i3", "name": "x", "originalAmount": 2.5, "unit": null, "order": 1}
            ]},
            {"id": "r4", "name": "String", "ingredients": [
              {"id": "i4", "name": "x", "originalAmount": "1/2", "unit": null, "order": 1}
            ]}
          ]
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(NativeExportPayload.self, from: json)

        let missing = payload.recipes[0].ingredients[0]
        XCTAssertNil(missing.originalAmount)
        XCTAssertNil(missing.amountText)

        let null = payload.recipes[1].ingredients[0]
        XCTAssertNil(null.originalAmount)
        XCTAssertNil(null.amountText)

        let number = payload.recipes[2].ingredients[0]
        XCTAssertEqual(number.originalAmount, 2.5)
        XCTAssertNil(number.amountText)

        let string = payload.recipes[3].ingredients[0]
        XCTAssertNil(string.originalAmount)
        XCTAssertEqual(string.amountText, "1/2")
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
}
