//
//  PublicImageDiskCache.swift
//  RecipeScalerNative
//

import CryptoKit
import Foundation

/// Ephemeral disk paths for public Discover images (Caches — iOS may purge).
enum PublicImageDiskCache {
    private static let baseFolderName = "PublicImages"

    static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static var baseDirectoryURL: URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent(baseFolderName, isDirectory: true)
    }

    static func fileURL(for url: URL) -> URL {
        baseDirectoryURL.appendingPathComponent("\(cacheKey(for: url)).webp")
    }

    static func existingFileURL(for url: URL) -> URL? {
        let file = fileURL(for: url)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}
