//
//  TimerLiveActivityMetadataProvider.swift
//  RecipeScalerNative
//

import Foundation
import UIKit
import RecipeScalerCore

struct TimerLiveActivityRecipeMetadata: Sendable {
    var recipeName: String?
    var thumbnailName: String?
}

@MainActor
enum TimerLiveActivityMetadataProvider {
    /// Installed from `ContentView` where `YjsSyncService` is available.
    static var recipeNameLookup: ((String) -> String?)?

    private static let appGroupIdentifier = AppGroup.id

    static func metadata(for recipeId: String?) async -> TimerLiveActivityRecipeMetadata {
        guard let recipeId, !recipeId.isEmpty else {
            return TimerLiveActivityRecipeMetadata()
        }

        let name = recipeNameLookup?(recipeId)
        let thumbnailName = await thumbnailName(recipeId: recipeId)
        return TimerLiveActivityRecipeMetadata(recipeName: name, thumbnailName: thumbnailName)
    }

    /// Thumbnail per recipe, keyed by the source image's modification date.
    /// `metadata(for:)` runs on every Live Activity sync (3–5 s ticks per timer),
    /// so the thumbnail is generated only when the source image changes.
    private static var thumbnailCache: [String: (sourceModified: Date, fileName: String)] = [:]

    /// Shown at 24 pt; 72 px stays sharp at 3x.
    private static let thumbnailMaxPixelSize = 72

    private static func thumbnailName(recipeId: String) async -> String? {
        guard let sourceURL = RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .preview)
            ?? RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .full),
              let sourceModified = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path))?[.modificationDate] as? Date
        else {
            return nil
        }
        if let cached = thumbnailCache[recipeId], cached.sourceModified == sourceModified {
            return cached.fileName
        }
        // The name carries the source version: an unchanged name means unchanged
        // pixels, so content dedupe in the coordinator stays correct.
        let fileName = "la-thumb-\(recipeId)-\(Int(sourceModified.timeIntervalSince1970)).jpg"
        let appGroupIdentifier = appGroupIdentifier
        let maxPixelSize = thumbnailMaxPixelSize
        let written = await Task.detached(priority: .utility) {
            writeThumbnail(
                from: sourceURL,
                recipeId: recipeId,
                fileName: fileName,
                maxPixelSize: maxPixelSize,
                appGroupIdentifier: appGroupIdentifier
            )
        }.value
        guard written else { return nil }
        thumbnailCache[recipeId] = (sourceModified, fileName)
        return fileName
    }

    /// ImageIO downsample + JPEG encode + write, off the main actor. Removes older
    /// versions of this recipe's thumbnail.
    private nonisolated static func writeThumbnail(
        from sourceURL: URL,
        recipeId: String,
        fileName: String,
        maxPixelSize: Int,
        appGroupIdentifier: String
    ) -> Bool {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return false }
        let thumbDir = container.appendingPathComponent("la-thumbs", isDirectory: true)
        let thumbURL = thumbDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: thumbURL.path) { return true }

        guard let image = RecipeImageDecoder.decode(fileURL: sourceURL, maxPixelSize: maxPixelSize),
              let jpegData = image.jpegData(compressionQuality: 0.7) else {
            return false
        }
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        do {
            try jpegData.write(to: thumbURL, options: .atomic)
        } catch {
            return false
        }
        let prefix = "la-thumb-\(recipeId)"
        let stale = (try? FileManager.default.contentsOfDirectory(atPath: thumbDir.path)) ?? []
        for name in stale where name != fileName && name.hasPrefix(prefix) && name.hasSuffix(".jpg") {
            let rest = name.dropFirst(prefix.count)
            // `la-thumb-<recipeId>.jpg` (pre-versioned) or `la-thumb-<recipeId>-<version>.jpg`.
            guard rest == ".jpg" || (rest.hasPrefix("-") && rest.dropFirst().dropLast(4).allSatisfy(\.isNumber)) else {
                continue
            }
            try? FileManager.default.removeItem(at: thumbDir.appendingPathComponent(name))
        }
        return true
    }

    static func thumbnailImage(name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let url = container.appendingPathComponent("la-thumbs/\(name)")
        return UIImage(contentsOfFile: url.path)
    }
}
