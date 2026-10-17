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
        .onChange(of: allowsNetworkRefresh) { wasAllowed, isAllowed in
            guard !wasAllowed, isAllowed else { return }
            Task { await reloadImage() }
        }
    }

    private var loadTaskKey: String {
        Self.loadTaskIdentity(url: url, maxPixelSize: maxPixelSize, fullWidthHero: fullWidthHero)
    }

    /// Stable `.task(id:)` identity — excludes `allowsNetworkRefresh` so connection flaps do not restart loads.
    static func loadTaskIdentity(url: URL?, maxPixelSize: Int, fullWidthHero: Bool) -> String {
        "\(url?.absoluteString ?? "")|\(maxPixelSize)|\(fullWidthHero)"
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
        // Inline pinch-to-zoom (spec 064). Подавляется пока фото грузится (`uiImage == nil`).
        // Зум-картинка рисуется корневым overlay в AppShellView поверх tab bar / nav bar.
        .heroPhotoPinchZoom(isEnabled: uiImage != nil, uiImage: uiImage)
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

        await applyImageFromDisk(sourceURL: url)

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

    /// The cached file, when there is one: hashing the URL and the disk lookup run off the
    /// main thread with the decode.
    private func applyImageFromDisk(sourceURL: URL) async {
        let maxPixelSize = maxPixelSize
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let fileURL = PublicImageDiskCache.existingFileURL(for: sourceURL) else { return nil }
            return RecipeImageDecoder.decode(fileURL: fileURL, maxPixelSize: maxPixelSize)
        }.value
        guard let decoded else { return }
        DiscoverImageMemoryCache.store(decoded, for: sourceURL)
        await MainActor.run {
            uiImage = decoded
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
