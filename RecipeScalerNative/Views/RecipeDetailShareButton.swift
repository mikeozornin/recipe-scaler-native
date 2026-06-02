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
            AppSymbol.image("square.and.arrow.up")
        }
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
                    Text(String(localized: "recipe.share.link"))
                }
                .presentationDetents([.medium])
            }
        }
    }
}