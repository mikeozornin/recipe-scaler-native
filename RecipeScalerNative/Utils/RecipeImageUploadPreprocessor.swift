//
//  RecipeImageUploadPreprocessor.swift
//  RecipeScalerNative
//

import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Prepared bytes for `POST /api/recipes/:id/image` (server limit 10 MB).
struct RecipeImageUploadPayload: Sendable {
    let data: Data
    let fileName: String
    let mimeType: String
}

/// HEIC/WebP passthrough (≤10 MB) → re-encoded WebP (if available) → JPEG fallback.
enum RecipeImageUploadPreprocessor {
    static let maxUploadBytes = 10_000_000

    private static let maxLongEdgePixels = 2560
    private static let targetMaxBytes = 9_500_000

    private static let webpEncodingAvailable: Bool = {
        let probe = NSMutableData()
        return CGImageDestinationCreateWithData(
            probe,
            UTType.webP.identifier as CFString,
            1,
            nil
        ) != nil
    }()

    static func payloadForUpload(from data: Data) -> RecipeImageUploadPayload? {
        let sourceType = imageSourceTypeIdentifier(data) ?? "unknown"

        if isHeicType(sourceType), data.count <= maxUploadBytes {
            return RecipeImageUploadPayload(
                data: data,
                fileName: heicFileName(for: sourceType),
                mimeType: heicMimeType(for: sourceType)
            )
        }

        if sourceType == UTType.webP.identifier, data.count <= maxUploadBytes {
            return RecipeImageUploadPayload(data: data, fileName: "photo.webp", mimeType: "image/webp")
        }

        guard let image = decodeImage(from: data) else {
            return nil
        }

        if webpEncodingAvailable, let webp = imageDataUnderLimit(image, format: .webp) {
            return RecipeImageUploadPayload(data: webp, fileName: "photo.webp", mimeType: "image/webp")
        }

        guard let jpeg = imageDataUnderLimit(image, format: .jpeg) else { return nil }
        return RecipeImageUploadPayload(data: jpeg, fileName: "photo.jpg", mimeType: "image/jpeg")
    }

    private enum OutputFormat {
        case webp
        case jpeg
    }

    private static func imageSourceTypeIdentifier(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            return nil
        }
        return type as String
    }

    private static func isHeicType(_ typeId: String?) -> Bool {
        guard let typeId else { return false }
        if typeId == UTType.heic.identifier || typeId == UTType.heif.identifier {
            return true
        }
        let lower = typeId.lowercased()
        return lower.contains("heic") || lower.contains("heif")
    }

    private static func heicFileName(for typeId: String?) -> String {
        typeId?.lowercased().contains("heif") == true ? "photo.heif" : "photo.heic"
    }

    private static func heicMimeType(for typeId: String?) -> String {
        typeId?.lowercased().contains("heif") == true ? "image/heif" : "image/heic"
    }

    private static func decodeImage(from data: Data) -> UIImage? {
        if let downsampled = downsampledImage(from: data, maxPixelSize: maxLongEdgePixels) {
            return downsampled
        }
        guard let fallback = UIImage(data: data) else { return nil }
        return normalizedUIImage(fallback)
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private static func normalizedUIImage(_ image: UIImage) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > CGFloat(maxLongEdgePixels) else {
            guard image.imageOrientation == .up, image.scale == 1 else {
                return render(image, pixelSize: CGSize(width: pixelWidth, height: pixelHeight))
            }
            return image
        }
        let scale = CGFloat(maxLongEdgePixels) / longEdge
        return render(
            image,
            pixelSize: CGSize(
                width: floor(pixelWidth * scale),
                height: floor(pixelHeight * scale)
            )
        )
    }

    private static func imageDataUnderLimit(_ image: UIImage, format: OutputFormat) -> Data? {
        var maxEdge = CGFloat(maxLongEdgePixels)
        var working = image

        for _ in 0..<14 {
            if let data = bestEncodedData(for: working, format: format, maxBytes: targetMaxBytes) {
                return data
            }
            maxEdge = max(480, maxEdge * 0.75)
            working = resizeToMaxLongEdge(working, maxEdge)
        }

        return bestEncodedData(for: working, format: format, maxBytes: targetMaxBytes)
    }

    private static func bestEncodedData(for image: UIImage, format: OutputFormat, maxBytes: Int) -> Data? {
        guard let cgImage = cgImage(from: image) else { return nil }
        let qualities: [Float] = [0.85, 0.72, 0.58, 0.45, 0.32, 0.2, 0.12, 0.08]
        for quality in qualities {
            let data: Data?
            switch format {
            case .webp:
                data = encodeWebP(cgImage: cgImage, quality: quality)
            case .jpeg:
                data = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
                    .jpegData(compressionQuality: CGFloat(quality))
            }
            guard let data, data.count <= maxBytes else { continue }
            return data
        }
        return nil
    }

    private static func encodeWebP(cgImage: CGImage, quality: Float) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.webP.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func cgImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }
        let rendered = render(
            image,
            pixelSize: CGSize(
                width: image.size.width * image.scale,
                height: image.size.height * image.scale
            )
        )
        return rendered.cgImage
    }

    private static func resizeToMaxLongEdge(_ image: UIImage, _ maxEdge: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > maxEdge else { return image }
        let scale = maxEdge / longEdge
        return render(
            image,
            pixelSize: CGSize(
                width: floor(pixelWidth * scale),
                height: floor(pixelHeight * scale)
            )
        )
    }

    private static func render(_ image: UIImage, pixelSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}