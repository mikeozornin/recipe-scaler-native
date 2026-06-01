//
//  RecipeCachedImageView.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

/// Displays a recipe image from the on-disk cache. Refreshes via API only when `allowsNetworkRefresh` is true.
struct RecipeCachedImageView: View {
    let recipeId: String
    let imageUrl: String?
    var variant: CachedImageVariant = .preview
    var allowsNetworkRefresh: Bool = true

    @State private var uiImage: UIImage?

    private var hasImageIndicator: Bool {
        guard let imageUrl, !imageUrl.isEmpty else { return false }
        return true
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .task(id: loadTaskKey) {
            await reloadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recipeImageDidCache)) { notification in
            guard let cachedId = notification.userInfo?["recipeId"] as? String,
                  cachedId == recipeId,
                  let rawVariant = notification.userInfo?["variant"] as? String,
                  rawVariant == variant.rawValue else {
                return
            }
            Task { await reloadFromDiskOnly() }
        }
    }

    private var loadTaskKey: String {
        "\(recipeId)|\(imageUrl ?? "")|\(variant.rawValue)|\(allowsNetworkRefresh)"
    }

    private func reloadImage() async {
        guard hasImageIndicator || uiImage != nil else {
            uiImage = nil
            return
        }

        if let fileURL = await RecipeImageService.shared.ensureCached(
            recipeId: recipeId,
            imageUrl: imageUrl,
            variant: variant,
            allowNetwork: allowsNetworkRefresh
        ) {
            uiImage = UIImage(contentsOfFile: fileURL.path)
        } else {
            uiImage = nil
        }
    }

    private func reloadFromDiskOnly() async {
        guard let fileURL = await RecipeImageService.shared.localFileURL(recipeId: recipeId, variant: variant) else {
            return
        }
        uiImage = UIImage(contentsOfFile: fileURL.path)
    }
}