import XCTest
import RecipeScalerCore

final class NativeFormatValidatorTests: XCTestCase {
    func testValidV14PayloadPasses() {
        let payload = NativeExportPayload(
            metadata: NativeExportMetadata(
                version: "1.4",
                exportDate: "2026-06-16T12:00:00Z",
                type: "recipes-v1.4",
                count: 1
            ),
            recipes: [
                NativeRecipe(
                    id: "recipe-1",
                    name: "Pasta",
                    ingredients: [NativeIngredient(name: "flour")],
                    folderIds: ["folder-1"]
                )
            ],
            folders: [
                NativeFolder(id: "folder-1", name: "Dinner")
            ],
            imageFiles: nil
        )

        let result = NativeFormatValidator.validate(payload: payload, version: .v1_4)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.recipeErrors.isEmpty)
        XCTAssertTrue(result.folderErrors.isEmpty)
    }

    func testEmptyRecipesFailsStructuralValidation() {
        let payload = NativeExportPayload(
            metadata: NativeExportMetadata(
                version: "1.0",
                exportDate: "2026-06-16T12:00:00Z"
            ),
            recipes: [],
            folders: nil,
            imageFiles: nil
        )

        let result = NativeFormatValidator.validate(payload: payload, version: .v1_0)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.structuralErrors.contains("recipes array is empty"))
    }

    func testRecipeMissingNameIsReported() {
        let payload = NativeExportPayload(
            metadata: NativeExportMetadata(
                version: "1.4",
                exportDate: "2026-06-16T12:00:00Z",
                type: "recipes-v1.4",
                count: 1
            ),
            recipes: [
                NativeRecipe(id: "recipe-1", name: "   ", ingredients: [])
            ],
            folders: nil,
            imageFiles: nil
        )

        let result = NativeFormatValidator.validate(payload: payload, version: .v1_4)
        XCTAssertEqual(result.recipeErrors.count, 1)
        XCTAssertTrue(result.recipeErrors[0].errors.contains("name is required"))
    }

    func testNegativeNutritionFailsForV12() {
        let payload = NativeExportPayload(
            metadata: NativeExportMetadata(
                version: "1.2",
                exportDate: "2026-06-16T12:00:00Z",
                type: "recipes-v1.2",
                count: 1
            ),
            recipes: [
                NativeRecipe(
                    id: "recipe-1",
                    name: "Soup",
                    ingredients: [],
                    nutrition: NativeNutrition(calories: -1)
                )
            ],
            folders: nil,
            imageFiles: nil
        )

        let result = NativeFormatValidator.validate(payload: payload, version: .v1_2)
        XCTAssertEqual(result.recipeErrors.count, 1)
        XCTAssertTrue(result.recipeErrors[0].errors.contains("nutrition.calories must be >= 0"))
    }
}
