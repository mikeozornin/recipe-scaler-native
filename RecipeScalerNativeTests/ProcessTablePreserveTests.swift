import XCTest
import YrsC
@testable import RecipeScalerNative

final class ProcessTablePreserveTests: XCTestCase {
    func testUpdateIngredientPreservesProcessTableRaw() async throws {
        let userId = "user-process-table-preserve"
        let ingredientId = "ing-pt"
        let tableJSON = """
        {"version":1,"sourceHash":"\(String(repeating: "d", count: 64))","columns":[{"id":"c1","title":"Mix","kind":"cook","stepIndex":0}],"assignments":[{"ingredientId":"\(ingredientId)","columnId":"c1"}]}
        """
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Process table")
        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "processTable", value: .string(tableJSON), txn: txn)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Tomato")),
                    ("amount", .string("2")),
                    ("order", .int(1)),
                ]),
            ]), txn: txn)
        }

        let renamed = IngredientData(
            id: ingredientId,
            name: "Cherry tomato",
            amount: "2",
            originalAmount: "2",
            unit: "",
            order: 1
        )
        try await manager.updateIngredient(recipeId: recipeId, ingredient: renamed)

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.processTableRaw, tableJSON)
        XCTAssertEqual(readBack?.ingredients.first?.name, "Cherry tomato")
    }
}
