//
//  ShoppingListPresentationTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class ShoppingViewModelGroupingTests: XCTestCase {

    private func snapshot(_ items: [ShoppingListItem], mode: ShoppingSortMode) -> ShoppingListSnapshot {
        ShoppingListSnapshot(items: items, meta: ShoppingListMeta(sortMode: mode, schemaVersion: 1))
    }

    func test_recipeMode_groupsByRecipe_manualItemsLast() {
        let model = ShoppingViewModel()
        model.recompute(
            snapshot: snapshot([
                ShoppingListItem(id: "milk", label: "Молоко"),
                ShoppingListItem(id: "beet", label: "Свёкла", recipeId: "r-borsch", recipeName: "Борщ"),
                ShoppingListItem(id: "eggs", label: "Яйца", recipeId: "r-carbonara", recipeName: "Карбонара"),
                ShoppingListItem(id: "cabbage", label: "Капуста", recipeId: "r-borsch", recipeName: "Борщ"),
                ShoppingListItem(id: "bought", label: "Лавр", recipeId: "r-borsch", recipeName: "Борщ", purchased: true),
            ], mode: .recipe),
            purchasePhases: [:]
        )

        XCTAssertEqual(model.toBuyGroups.map(\.recipeTitle), ["Борщ", "Карбонара", nil])
        XCTAssertEqual(model.toBuyGroups.map { $0.items.map(\.id) }, [["cabbage", "beet"], ["eggs"], ["milk"]])
        XCTAssertTrue(model.toBuyGroups.last?.isMisc == true)
        XCTAssertEqual(model.sortedPurchased.map(\.id), ["bought"])
    }

    func test_recipeMode_stagedItemStaysInItsRecipeGroup() {
        let model = ShoppingViewModel()
        model.recompute(
            snapshot: snapshot([
                ShoppingListItem(id: "beet", label: "Свёкла", recipeId: "r-borsch", recipeName: "Борщ", purchased: true),
            ], mode: .recipe),
            purchasePhases: ["beet": .exiting]
        )

        XCTAssertEqual(model.toBuyGroups.map { $0.items.map(\.id) }, [["beet"]])
    }

    func test_alphabetMode_hasNoGroups() {
        let model = ShoppingViewModel()
        model.recompute(
            snapshot: snapshot([
                ShoppingListItem(id: "beet", label: "Свёкла", recipeId: "r-borsch", recipeName: "Борщ"),
                ShoppingListItem(id: "milk", label: "Молоко"),
            ], mode: .alphabet),
            purchasePhases: [:]
        )

        XCTAssertTrue(model.toBuyGroups.isEmpty)
        XCTAssertEqual(model.sortedToBuy.map(\.id), ["milk", "beet"])
    }
}

final class ShoppingLabelTests: XCTestCase {

    func test_label_dropsUnitAlreadyInIngredientName() {
        let ingredient = IngredientData(id: "water", name: "Вода, мл", amount: "100", originalAmount: "100", unit: "мл")
        XCTAssertEqual(ShoppingListFromRecipe.label(for: ingredient), "100 · Вода, мл")
    }

    func test_label_keepsUnitWhenNameHasNoUnit() {
        let ingredient = IngredientData(id: "water", name: "Вода", amount: "100", originalAmount: "100", unit: "мл")
        XCTAssertEqual(ShoppingListFromRecipe.label(for: ingredient), "100 мл · Вода")
    }

    func test_displayLabel_compactsLegacyLabels() {
        XCTAssertEqual(ShoppingListFromRecipe.displayLabel(for: "100 мл · Вода, мл"), "100 · Вода, мл")
        XCTAssertEqual(
            ShoppingListFromRecipe.displayLabel(for: "1 чайная ложка · Соль, чайная ложка"),
            "1 · Соль, чайная ложка"
        )
        XCTAssertEqual(ShoppingListFromRecipe.displayLabel(for: "1,5 кг · Мука, г"), "1,5 кг · Мука, г")
        XCTAssertEqual(ShoppingListFromRecipe.displayLabel(for: "Молоко, мл"), "Молоко, мл")
        XCTAssertEqual(ShoppingListFromRecipe.displayLabel(for: "Хлеб"), "Хлеб")
    }
}
