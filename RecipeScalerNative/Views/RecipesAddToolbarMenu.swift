//
//  RecipesAddToolbarMenu.swift
//  RecipeScalerNative
//

import SwiftUI

/// Toolbar "+" menu on the Recipes tab: create blank recipe or open import sheet.
struct RecipesAddToolbarMenu: View {
    var isCreatingRecipe: Bool
    var onCreateRecipe: () -> Void
    var onImport: () -> Void

    var body: some View {
        Menu {
            Button {
                onCreateRecipe()
            } label: {
                AppLabel.make("recipe.create.new", symbol: "plus")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeListAddNew)

            Button {
                onImport()
            } label: {
                AppLabel.make("recipes.import-button", symbol: "square.and.arrow.down")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeListImport)
        } label: {
            AppToolbarStyle.iconOnly(systemName: "plus")
        }
        .appToolbarIconButton()
        .disabled(isCreatingRecipe)
        .accessibilityLabel("recipes.add-button")
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeListAdd)
    }
}
