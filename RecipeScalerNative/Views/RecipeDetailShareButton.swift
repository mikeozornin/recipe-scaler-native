//
//  RecipeDetailShareButton.swift
//  RecipeScalerNative
//

import SwiftUI

struct RecipeDetailShareButton: View {
    let recipeId: String

    @State private var showShare = false
    @State private var shareURL: URL?

    var body: some View {
        Button {
            shareURL = PublicURLBuilder.recipeShareURL(recipeId: recipeId)
            showShare = shareURL != nil
        } label: {
            AppToolbarStyle.iconOnly(systemName: "square.and.arrow.up")
        }
        .appToolbarIconButton()
        .accessibilityLabel(String(localized: "recipe.share"))
        #if DEBUG
        .onAppear {
            if DebugLaunchOptions.showRecipeShare {
                shareURL = PublicURLBuilder.recipeShareURL(recipeId: recipeId)
                if shareURL != nil {
                    showShare = true
                }
            }
        }
        #endif
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ShareLink(item: shareURL) {
                    Text("recipe.share.link")
                        .font(AppTypography.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .presentationDetents([.medium])
            }
        }
    }
}