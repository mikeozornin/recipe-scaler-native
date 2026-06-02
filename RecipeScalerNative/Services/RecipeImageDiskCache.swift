//
//  RecipeImageDiskCache.swift
//  RecipeScalerNative
//

import Foundation

/// Synchronous disk paths for recipe images (no actor hop — safe for SwiftUI `.task`).
enum RecipeImageDiskCache {
    private static let baseFolderName = "RecipeImages"

    static func fileURL(recipeId: String, variant: CachedImageVariant) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folderURL = cachesDir.appendingPathComponent(baseFolderName, isDirectory: true)
        return folderURL.appendingPathComponent("\(recipeId)_\(variant.rawValue).webp")
    }

    static func existingFileURL(recipeId: String, variant: CachedImageVariant) -> URL? {
        let url = fileURL(recipeId: recipeId, variant: variant)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}