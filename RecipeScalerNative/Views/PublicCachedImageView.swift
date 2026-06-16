//
//  PublicCachedImageView.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

/// Displays a public image from disk cache (Caches/PublicImages). Refreshes via ETag when allowed.
struct PublicCachedImageView: View {
    let url: URL?
    var allowsNetworkRefresh: Bool = true
    var maxPixelSize: Int = RecipeImageDecoder.fullMaxPixelSize
    /// Stored width/height ratio. Used for hero layout when set.
    var layoutAspectRatio: CGFloat?
    var fullWidthHero: Bool = false
    var maxHeight: CGFloat?
    var contentMode: ContentMode = .fill

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if fullWidthHero {
                heroImageBody
            } else {
                imageBody
            }
        }
        .task(id: loadTaskKey) {
            await reloadImage()
        }
    }

    private var loadTaskKey: String {
        "\(url?.absoluteString ?? "")|\(allowsNetworkRefresh)|\(maxPixelSize)|\(fullWidthHero)"
    }

    @ViewBuilder
    private var imageBody: some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Color.clear
        }
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
        .aspectRatio(heroAspectRatio, contentMode: .fill)
        .frame(maxHeight: cap)
        .clipped()
    }

    private var heroAspectRatio: CGFloat {
        if let layoutAspectRatio, layoutAspectRatio > 0 {
            return layoutAspectRatio
        }
        if let uiImage, uiImage.size.height > 0 {
            return uiImage.size.width / uiImage.size.height
        }
        return 4 / 3
    }

    private func reloadImage() async {
        guard let url else {
            await MainActor.run { uiImage = nil }
            return
        }

        if let cached = DiscoverImageMemoryCache.image(for: url) {
            await MainActor.run { uiImage = cached }
        }

        if let fileURL = PublicImageDiskCache.existingFileURL(for: url) {
            await applyImage(from: fileURL, sourceURL: url)
        }

        guard allowsNetworkRefresh else { return }

        if let fileURL = await PublicImageCacheService.shared.ensureCached(
            url: url,
            allowNetwork: true
        ) {
            await applyImage(from: fileURL, sourceURL: url)
        } else if uiImage == nil {
            await MainActor.run { uiImage = nil }
        }
    }

    private func applyImage(from fileURL: URL, sourceURL: URL) async {
        let maxPixelSize = maxPixelSize
        let decoded = await Task.detached(priority: .userInitiated) {
            RecipeImageDecoder.decode(fileURL: fileURL, maxPixelSize: maxPixelSize)
        }.value
        guard let decoded else { return }
        DiscoverImageMemoryCache.store(decoded, for: sourceURL)
        await MainActor.run {
            uiImage = decoded
        }
    }
}
