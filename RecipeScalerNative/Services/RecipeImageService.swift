//
//  RecipeImageService.swift
//  RecipeScalerNative
//

import Foundation

extension Notification.Name {
    /// Posted when a recipe image file was written to disk. `userInfo`: `recipeId`, `variant` (CachedImageVariant rawValue).
    static let recipeImageDidCache = Notification.Name("recipeImageDidCache")
}

/// Stable cache-busting token from Y.Doc `imageUrl` (storage path), matching web `imageVersionToken`.
enum RecipeImageVersion {
    static func token(from imageUrl: String?) -> String? {
        guard let imageUrl, !imageUrl.isEmpty else { return nil }
        let segment = imageUrl.split(separator: "/").last.map(String.init) ?? imageUrl
        guard let dot = segment.lastIndex(of: ".") else { return segment }
        return String(segment[..<dot])
    }
}

/// Offline-first recipe images: REST download → `ImageCacheService` files; UI reads local paths only.
actor RecipeImageService {
    static let shared = RecipeImageService()

    private let defaults = UserDefaults.standard
    private var inFlight = Set<String>()
    private let prefetchConcurrency = 3

    private init() {}

    func localFileURL(recipeId: String, variant: CachedImageVariant) async -> URL? {
        await ImageCacheService.shared.cachedImageURL(recipeId: recipeId, variant: variant)
    }

    /// Returns a cached file URL, optionally refreshing from the API when allowed.
    func ensureCached(
        recipeId: String,
        imageUrl: String?,
        variant: CachedImageVariant,
        allowNetwork: Bool
    ) async -> URL? {
        guard let imageUrl, !imageUrl.isEmpty else {
            await removeCache(recipeId: recipeId)
            return nil
        }

        let version = RecipeImageVersion.token(from: imageUrl)
        if let local = await ImageCacheService.shared.cachedImageURL(recipeId: recipeId, variant: variant),
           storedVersion(recipeId: recipeId, variant: variant) == version {
            return local
        }

        guard allowNetwork else {
            return await ImageCacheService.shared.cachedImageURL(recipeId: recipeId, variant: variant)
        }

        return await fetchAndStore(recipeId: recipeId, imageUrl: imageUrl, variant: variant)
    }

    func prefetchPreviews(entries: [CollectionEntry], allowNetwork: Bool) async {
        for entry in entries {
            if entry.imageUrl?.isEmpty != false {
                await removeCache(recipeId: entry.id)
            }
        }

        guard allowNetwork else { return }

        let candidates = entries.filter { entry in
            guard let url = entry.imageUrl, !url.isEmpty else { return false }
            return true
        }
        guard !candidates.isEmpty else { return }

        var index = 0
        await withTaskGroup(of: Void.self) { group in
            let initial = min(prefetchConcurrency, candidates.count)
            while index < initial {
                let entry = candidates[index]
                index += 1
                group.addTask { await self.prefetchPreview(entry) }
            }

            for await _ in group {
                guard index < candidates.count else { continue }
                let entry = candidates[index]
                index += 1
                group.addTask { await self.prefetchPreview(entry) }
            }
        }
    }

    func prefetchFull(recipeId: String, imageUrl: String?, allowNetwork: Bool) async {
        guard allowNetwork else { return }
        _ = await ensureCached(
            recipeId: recipeId,
            imageUrl: imageUrl,
            variant: .full,
            allowNetwork: true
        )
    }

    func removeCache(recipeId: String) async {
        await ImageCacheService.shared.removeCached(recipeId: recipeId)
        for variant in [CachedImageVariant.preview, .full] {
            defaults.removeObject(forKey: etagKey(recipeId: recipeId, variant: variant))
            defaults.removeObject(forKey: lastModifiedKey(recipeId: recipeId, variant: variant))
            defaults.removeObject(forKey: versionKey(recipeId: recipeId, variant: variant))
        }
    }

    // MARK: - Private

    private func fetchAndStore(
        recipeId: String,
        imageUrl: String,
        variant: CachedImageVariant
    ) async -> URL? {
        let flightKey = "\(recipeId):\(variant.rawValue)"
        guard !inFlight.contains(flightKey) else {
            return await ImageCacheService.shared.cachedImageURL(recipeId: recipeId, variant: variant)
        }
        inFlight.insert(flightKey)
        defer { inFlight.remove(flightKey) }

        let version = RecipeImageVersion.token(from: imageUrl)
        guard let remoteURL = await APIClient.shared.recipeImageURL(
            id: recipeId,
            preview: variant == .preview,
            version: version
        ) else {
            return nil
        }

        do {
            let result = try await ImageCacheService.shared.fetchAndCache(
                recipeId: recipeId,
                variant: variant,
                remoteURL: remoteURL,
                etag: storedEtag(recipeId: recipeId, variant: variant),
                lastModified: storedLastModified(recipeId: recipeId, variant: variant)
            )
            storeMetadata(
                recipeId: recipeId,
                variant: variant,
                version: version,
                etag: result.etag,
                lastModified: result.lastModified
            )
            await notifyCached(recipeId: recipeId, variant: variant)
            return result.localURL
        } catch {
            return await ImageCacheService.shared.cachedImageURL(recipeId: recipeId, variant: variant)
        }
    }

    private func prefetchPreview(_ entry: CollectionEntry) async {
        _ = await ensureCached(
            recipeId: entry.id,
            imageUrl: entry.imageUrl,
            variant: .preview,
            allowNetwork: true
        )
    }

    private func notifyCached(recipeId: String, variant: CachedImageVariant) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .recipeImageDidCache,
                object: nil,
                userInfo: [
                    "recipeId": recipeId,
                    "variant": variant.rawValue,
                ]
            )
        }
    }

    private func storedVersion(recipeId: String, variant: CachedImageVariant) -> String? {
        defaults.string(forKey: versionKey(recipeId: recipeId, variant: variant))
    }

    private func storedEtag(recipeId: String, variant: CachedImageVariant) -> String? {
        defaults.string(forKey: etagKey(recipeId: recipeId, variant: variant))
    }

    private func storedLastModified(recipeId: String, variant: CachedImageVariant) -> String? {
        defaults.string(forKey: lastModifiedKey(recipeId: recipeId, variant: variant))
    }

    private func storeMetadata(
        recipeId: String,
        variant: CachedImageVariant,
        version: String?,
        etag: String?,
        lastModified: String?
    ) {
        if let version {
            defaults.set(version, forKey: versionKey(recipeId: recipeId, variant: variant))
        }
        if let etag {
            defaults.set(etag, forKey: etagKey(recipeId: recipeId, variant: variant))
        } else {
            defaults.removeObject(forKey: etagKey(recipeId: recipeId, variant: variant))
        }
        if let lastModified {
            defaults.set(lastModified, forKey: lastModifiedKey(recipeId: recipeId, variant: variant))
        } else {
            defaults.removeObject(forKey: lastModifiedKey(recipeId: recipeId, variant: variant))
        }
    }

    private func etagKey(recipeId: String, variant: CachedImageVariant) -> String {
        "recipeImage.\(recipeId).\(variant.rawValue).etag"
    }

    private func lastModifiedKey(recipeId: String, variant: CachedImageVariant) -> String {
        "recipeImage.\(recipeId).\(variant.rawValue).lastModified"
    }

    private func versionKey(recipeId: String, variant: CachedImageVariant) -> String {
        "recipeImage.\(recipeId).\(variant.rawValue).version"
    }
}