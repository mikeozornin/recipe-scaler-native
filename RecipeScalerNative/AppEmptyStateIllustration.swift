//
//  AppEmptyStateIllustration.swift
//  RecipeScalerNative
//

import SwiftUI

/// Asset catalog names for empty-state hero illustrations (see `sync-empty-state-illustrations.mjs`).
enum EmptyStateIllustrationAsset: String {
    case recipeNotebookEmpty = "empty-state-recipe-notebook"
    case shoppingBasketEmpty = "empty-state-shopping-basket-empty"
    case shoppingBasketFull = "empty-state-shopping-basket-full"
}

/// Pencil-soft empty-state art at `AppTypography.emptyStateIllustrationSize` (192 pt).
struct AppEmptyStateIllustration: View {
    let asset: EmptyStateIllustrationAsset

    var body: some View {
        Image(asset.rawValue)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(
                width: AppTypography.emptyStateIllustrationSize,
                height: AppTypography.emptyStateIllustrationSize
            )
            .accessibilityHidden(true)
    }
}