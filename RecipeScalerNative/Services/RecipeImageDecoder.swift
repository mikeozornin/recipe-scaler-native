//
//  RecipeImageDecoder.swift
//  RecipeScalerNative
//

import ImageIO
import UIKit

/// Downsampled decode for display — avoids loading multi‑MP full WebP into memory.
enum RecipeImageDecoder {
    static let previewMaxPixelSize: Int = 132
    static let fullMaxPixelSize: Int = 800

    static func maxPixelSize(for variant: CachedImageVariant) -> Int {
        switch variant {
        case .preview:
            return previewMaxPixelSize
        case .full:
            return fullMaxPixelSize
        }
    }

    static func decode(fileURL: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return decode(source: source, maxPixelSize: maxPixelSize)
    }

    static func decode(data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decode(source: source, maxPixelSize: maxPixelSize)
    }

    private static func decode(source: CGImageSource, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// In-memory cache of downsampled `UIImage` (keyed by file path + mod date + variant).
enum RecipeImageDisplayCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 80
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    static func image(fileURL: URL, variant: CachedImageVariant) -> UIImage? {
        let maxPixels = RecipeImageDecoder.maxPixelSize(for: variant)
        let key = cacheKey(fileURL: fileURL, maxPixels: maxPixels)
        if let hit = cache.object(forKey: key) {
            return hit
        }
        guard let decoded = RecipeImageDecoder.decode(fileURL: fileURL, maxPixelSize: maxPixels) else {
            return nil
        }
        let cost = decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(decoded, forKey: key, cost: cost)
        return decoded
    }

    private static func cacheKey(fileURL: URL, maxPixels: Int) -> NSString {
        let mod = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?
            .timeIntervalSince1970 ?? 0
        return "\(fileURL.path)|\(maxPixels)|\(mod)" as NSString
    }
}