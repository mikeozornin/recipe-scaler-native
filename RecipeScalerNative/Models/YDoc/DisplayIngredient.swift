//
//  DisplayIngredient.swift
//  RecipeScalerNative
//
//  Simple value type for displaying an ingredient row in detail views.
//  Extracted from the legacy `RecipeDetailView` so the Y.Doc-backed
//  `YDocRecipeDetailView` / `RecipeDetailViewModel` can reuse it without
//  pulling in the unreachable SwiftData `Recipe` model.
//

import Foundation

struct DisplayIngredient: Identifiable {
    let id: String
    let name: String
    let originalAmount: Double?
    let unit: String
    let order: Int
    let isSeparator: Bool
    /// Preformatted amount for Y.Doc rows (e.g. `"200 g"`); when set, shown instead of numeric scaling.
    var amountDisplay: String? = nil
}
