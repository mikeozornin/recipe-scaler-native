import XCTest
import YrsC
@testable import RecipeScalerNative

final class IngredientIllustrationBindingPersistenceTests: XCTestCase {
    func testUpdateIngredientPreservesIllustrationBindingWhenRenaming() async throws {
        let userId = "user-illustration-binding"
        let ingredientId = "ing-bound"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Binding")
        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Tomato")),
                    ("amount", .string("2")),
                    ("order", .int(1)),
                    ("illustrationId", .string("tomato")),
                ]),
            ]), txn: txn)
        }

        let renamed = IngredientData(
            id: ingredientId,
            name: "Cherry tomato",
            amount: "2",
            originalAmount: "2",
            unit: "",
            order: 1,
            illustrationId: "tomato",
            illustrationPickerCleared: false
        )
        try await manager.updateIngredient(recipeId: recipeId, ingredient: renamed)

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.ingredients.first?.illustrationId, "tomato")
        XCTAssertFalse(readBack?.ingredients.first?.illustrationPickerCleared ?? true)
    }

    func testLazyResolveBatchSkipsRowWhenNameChangedBeforeWrite() async throws {
        let userId = "user-lazy-guard"
        let ingredientId = "ing-guard"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Lazy guard")
        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Помидоры")),
                    ("amount", .string("1")),
                    ("order", .int(1)),
                ]),
            ]), txn: txn)
        }

        try await manager.updateIngredientIllustrationBindings(
            recipeId: recipeId,
            bindings: [
                (ingredientId: ingredientId, illustrationId: "tomato", pickerCleared: false, expectedName: "Помидоры"),
            ]
        )

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.ingredients.first?.illustrationId, "tomato")

        let renamed = IngredientData(
            id: ingredientId,
            name: "Cherry tomatoes",
            amount: "1",
            originalAmount: "1",
            unit: "",
            order: 1,
            illustrationId: "tomato",
            illustrationPickerCleared: false
        )
        try await manager.updateIngredient(recipeId: recipeId, ingredient: renamed)

        try await manager.updateIngredientIllustrationBindings(
            recipeId: recipeId,
            bindings: [
                (ingredientId: ingredientId, illustrationId: "cherry-tomato", pickerCleared: false, expectedName: "Помидоры"),
            ]
        )

        let afterStale = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(afterStale?.ingredients.first?.illustrationId, "tomato")
    }
}