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
    /// Stored width/height ratio from Y.Doc (`imageAspectRatio`). Used when `preservesAspectRatio` is true.
    var layoutAspectRatio: CGFloat?
    /// When true, image keeps its proportions (web `object-contain`).
    var preservesAspectRatio: Bool = false
    /// Recipe detail hero: full width, `object-cover` in aspect-ratio box (web `RecipeImageUpload` + `edgeToEdge`).
    var fullWidthHero: Bool = false
    var maxHeight: CGFloat?

    @State private var uiImage: UIImage?

    private var hasImageIndicator: Bool {
        guard let imageUrl, !imageUrl.isEmpty else { return false }
        return true
    }

    var body: some View {
        Group {
            if fullWidthHero {
                heroImageBody
            } else if let uiImage {
                if preservesAspectRatio {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(effectiveAspectRatio(for: uiImage), contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                Color.clear
            }
        }
        .task(id: loadTaskKey) {
            await reloadImage()
        }
        .onChange(of: allowsNetworkRefresh) { wasAllowed, isAllowed in
            guard !wasAllowed, isAllowed else { return }
            Task { await reloadImage() }
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
        Self.loadTaskIdentity(recipeId: recipeId, imageUrl: imageUrl, variant: variant)
    }

    /// Stable `.task(id:)` identity — excludes `allowsNetworkRefresh` so connection flaps do not restart loads.
    static func loadTaskIdentity(recipeId: String, imageUrl: String?, variant: CachedImageVariant) -> String {
        "\(recipeId)|\(imageUrl ?? "")|\(variant.rawValue)"
    }

    private func effectiveAspectRatio(for image: UIImage) -> CGFloat {
        if let layoutAspectRatio, layoutAspectRatio > 0 {
            return layoutAspectRatio
        }
        let size = image.size
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private var heroAspectRatio: CGFloat {
        if let layoutAspectRatio, layoutAspectRatio > 0 {
            return layoutAspectRatio
        }
        if let uiImage {
            return effectiveAspectRatio(for: uiImage)
        }
        return 4 / 3
    }

    @ViewBuilder
    private var heroImageBody: some View {
        let cap = maxHeight ?? 400
        ZStack {
            Color(.secondarySystemBackground)
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxWidth: .infinity)
        // `.fill` keeps full width when height is capped (web: `w-full` + `max-height` + `object-cover`).
        .aspectRatio(heroAspectRatio, contentMode: .fill)
        .frame(maxHeight: cap)
        .clipped()
    }

    private func reloadImage() async {
        guard hasImageIndicator || uiImage != nil else {
            await MainActor.run { uiImage = nil }
            return
        }

        // Fast path: read .webp from Caches without waiting on the image actor queue.
        if let fileURL = RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: variant) {
            await applyImage(from: fileURL)
        }

        guard allowsNetworkRefresh else { return }

        if let fileURL = await RecipeImageService.shared.ensureCached(
            recipeId: recipeId,
            imageUrl: imageUrl,
            variant: variant,
            allowNetwork: true
        ) {
            await applyImage(from: fileURL)
        } else if uiImage == nil {
            await MainActor.run { uiImage = nil }
        }
    }

    private func reloadFromDiskOnly() async {
        guard let fileURL = RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: variant) else {
            return
        }
        await applyImage(from: fileURL)
    }

    private func applyImage(from fileURL: URL) async {
        let variant = variant
        let decoded = await Task.detached(priority: .userInitiated) {
            RecipeImageDisplayCache.image(fileURL: fileURL, variant: variant)
        }.value
        guard let decoded else { return }
        await MainActor.run {
            uiImage = decoded
        }
    }
}