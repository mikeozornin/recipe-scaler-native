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
    /// Shim: returns `AppContainer.shared.imageCache` when the container is
    /// constructed, otherwise a lazily-instantiated stand-alone actor.
    static var shared: ImageCacheService {
        if let container = AppContainer.shared {
            return container.imageCache
        }
        return Standalone
    }

    private static let Standalone = ImageCacheService()

    private let fileManager = FileManager.default

    init() {}

    func cachedImageURL(recipeId: String, variant: CachedImageVariant) -> URL? {
        RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: variant)
    }

    func removeCached(recipeId: String) {
        for variant in [CachedImageVariant.preview, CachedImageVariant.full] {
            let url = RecipeImageDiskCache.fileURL(recipeId: recipeId, variant: variant)
            try? fileManager.removeItem(at: url)
        }
    }

    func fetchAndCache(
        recipeId: String,
        variant: CachedImageVariant,
        request: URLRequest
    ) async throws -> CachedImageResult {
        let localURL = RecipeImageDiskCache.fileURL(recipeId: recipeId, variant: variant)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let statusCode = httpResponse.statusCode
        let requestEtag = request.value(forHTTPHeaderField: "If-None-Match")
        let requestLastModified = request.value(forHTTPHeaderField: "If-Modified-Since")
        let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag") ?? requestEtag
        let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified") ?? requestLastModified

        if statusCode == 304 {
            if !fileManager.fileExists(atPath: localURL.path) {
                // Cache is missing, retry without validators
                var retry = request
                retry.setValue(nil, forHTTPHeaderField: "If-None-Match")
                retry.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
                return try await fetchAndCache(
                    recipeId: recipeId,
                    variant: variant,
                    request: retry
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

    private func ensureBaseDirectoryExists() throws {
        let folderURL = RecipeImageDiskCache.fileURL(recipeId: "_", variant: .preview).deletingLastPathComponent()
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }
}

