//
//  ImageCacheService.swift
//  RecipeScalerNative
//

import Foundation

enum CachedImageVariant: String {
    case preview
    case full
}

struct CachedImageResult {
    let localURL: URL
    let etag: String?
    let lastModified: String?
    let statusCode: Int
}

actor ImageCacheService {
    static let shared = ImageCacheService()

    private let fileManager = FileManager.default
    private let baseFolderName = "RecipeImages"

    private init() {}

    func cachedImageURL(recipeId: String, variant: CachedImageVariant) -> URL? {
        let url = localURL(recipeId: recipeId, variant: variant)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func fetchAndCache(
        recipeId: String,
        variant: CachedImageVariant,
        remoteURL: URL,
        etag: String?,
        lastModified: String?
    ) async throws -> CachedImageResult {
        let localURL = localURL(recipeId: recipeId, variant: variant)

        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        } else if let lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let statusCode = httpResponse.statusCode
        let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag") ?? etag
        let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified") ?? lastModified

        if statusCode == 304 {
            if !fileManager.fileExists(atPath: localURL.path) {
                // Cache is missing, retry without validators
                return try await fetchAndCache(
                    recipeId: recipeId,
                    variant: variant,
                    remoteURL: remoteURL,
                    etag: nil,
                    lastModified: nil
                )
            }
            return CachedImageResult(
                localURL: localURL,
                etag: responseEtag,
                lastModified: responseLastModified,
                statusCode: statusCode
            )
        }

        guard (200...299).contains(statusCode) else {
            throw URLError(.badServerResponse)
        }

        try ensureBaseDirectoryExists()
        try data.write(to: localURL, options: .atomic)

        return CachedImageResult(
            localURL: localURL,
            etag: responseEtag,
            lastModified: responseLastModified,
            statusCode: statusCode
        )
    }

    private func localURL(recipeId: String, variant: CachedImageVariant) -> URL {
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folderURL = cachesDir.appendingPathComponent(baseFolderName, isDirectory: true)
        let filename = "\(recipeId)_\(variant.rawValue).webp"
        return folderURL.appendingPathComponent(filename)
    }

    private func ensureBaseDirectoryExists() throws {
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folderURL = cachesDir.appendingPathComponent(baseFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }
}

