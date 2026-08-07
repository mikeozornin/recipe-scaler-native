//
//  DiscoverRecipePreviewImage.swift
//  RecipeScalerNative
//

import SwiftUI
import RecipeScalerCore

/// In-memory cache so eager grid cells restore instantly on re-scroll.
enum DiscoverImageMemoryCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// Discover grid image loader (public URLs, no auth).
enum DiscoverImageLoader {
    static let gridMaxPixelSize = RecipeImageDecoder.fullMaxPixelSize

    static func loadImage(from url: URL) async -> UIImage? {
        if let cached = DiscoverImageMemoryCache.image(for: url) {
            return cached
        }
        if let fileURL = PublicImageDiskCache.existingFileURL(for: url),
           let image = RecipeImageDecoder.decode(
               fileURL: fileURL,
               maxPixelSize: gridMaxPixelSize
           ) {
            DiscoverImageMemoryCache.store(image, for: url)
            return image
        }
        guard let fileURL = await PublicImageCacheService.shared.ensureCached(
            url: url,
            allowNetwork: true
        ),
              let image = RecipeImageDecoder.decode(
                  fileURL: fileURL,
                  maxPixelSize: gridMaxPixelSize
              ) else {
            return nil
        }
        DiscoverImageMemoryCache.store(image, for: url)
        return image
    }
}

/// Preview for Discover / Public Profile recipe grids.
///
/// Uses full-size discover/public URLs (web parity), 16:9 `object-cover`, memory +
/// disk cache (`Caches/PublicImages/`) with ETag revalidation.
struct DiscoverRecipePreviewImage: View {
    let url: URL?
    let fallbackColor: Color
    var cornerRadius: CGFloat = 12
    var aspectRatio: CGFloat = 16.0 / 9.0

    @State private var loadedImage: UIImage?

    private var displayedImage: UIImage? {
        if let loadedImage { return loadedImage }
        guard let url else { return nil }
        return DiscoverImageMemoryCache.image(for: url)
    }

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(fallbackColor.opacity(0.15))
            .overlay {
                ZStack {
                    if let displayedImage {
                        Image(uiImage: displayedImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
            .task(id: url) {
                await loadIfNeeded()
            }
    }

    private var placeholder: some View {
        AppSymbol.image("photo")
            .font(.system(size: 28, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fallbackColor.opacity(0.12))
    }

    private func loadIfNeeded() async {
        guard let url else {
            loadedImage = nil
            return
        }
        if let cached = DiscoverImageMemoryCache.image(for: url) {
            loadedImage = cached
            return
        }
        loadedImage = await DiscoverImageLoader.loadImage(from: url)
    }
}

extension DiscoverRecipePreviewImage {
    init(absoluteURL: String?, fallbackColor: Color) {
        let url: URL? = {
            guard let absoluteURL, !absoluteURL.isEmpty else { return nil }
            if let parsed = URL(string: absoluteURL), parsed.scheme != nil {
                return parsed
            }
            let separator = absoluteURL.hasPrefix("/") ? "" : "/"
            return URL(string: "\(Config.baseURL)\(separator)\(absoluteURL)")
        }()
        self.init(url: url, fallbackColor: fallbackColor)
    }
}
