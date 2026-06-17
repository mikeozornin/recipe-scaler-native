//
//  RecipeImageDiskCache.swift
//  RecipeScalerNative
//

import Foundation

/// Synchronous disk paths for personal recipe images (Application Support — persistent).
enum RecipeImageDiskCache {
    private static let baseFolderName = "RecipeImages"
    private static let legacyBaseFolderName = "RecipeImages"
    private static let migrationKey = "recipeImage.diskCache.migratedToApplicationSupport"

    static func fileURL(recipeId: String, variant: CachedImageVariant) -> URL {
        let folderURL = baseDirectoryURL
        return folderURL.appendingPathComponent("\(recipeId)_\(variant.rawValue).webp")
    }

    static func existingFileURL(recipeId: String, variant: CachedImageVariant) -> URL? {
        let url = fileURL(recipeId: recipeId, variant: variant)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var baseDirectoryURL: URL {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return supportDir.appendingPathComponent(baseFolderName, isDirectory: true)
    }

    static var legacyCachesDirectoryURL: URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent(legacyBaseFolderName, isDirectory: true)
    }

    /// One-time move from Caches → Application Support (spec 003 → Application Support).
    static func migrateFromCachesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let fileManager = FileManager.default
        let legacyDir = legacyCachesDirectoryURL
        let targetDir = baseDirectoryURL

        defer {
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        guard fileManager.fileExists(atPath: legacyDir.path) else {
            try? fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
            return
        }

        try? fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)

        guard let legacyFiles = try? fileManager.contentsOfDirectory(
            at: legacyDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var movedCount = 0
        for source in legacyFiles {
            let destination = targetDir.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: source)
                continue
            }
            do {
                try fileManager.moveItem(at: source, to: destination)
                movedCount += 1
            } catch {
                continue
            }
        }

        if movedCount > 0 {
            #if DEBUG
            AppLog.info(.app, "RecipeImageDiskCache: migrated \(movedCount) file(s) from Caches to Application Support")
            #endif
        }

        try? fileManager.removeItem(at: legacyDir)
    }
}
