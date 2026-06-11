//
//  RecipeImageService.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

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
    /// Parallel HTTP downloads (previews first, then full).
    private let prefetchConcurrency = 8
    private var isPrefetching = false
    private var prefetchCompleted = 0
    private var prefetchTotal = 0
    private var cacheStatusNotifyTask: Task<Void, Never>?

    private init() {}

    func localFileURL(recipeId: String, variant: CachedImageVariant) async -> URL? {
        await ImageCacheService.shared.cachedImageURL(recipeId: recipeId, variant: variant)
    }

    /// Snapshot of disk cache vs collection entries (no network).
    func cacheStatus(for entries: [CollectionEntry]) async -> RecipeImageCacheStatus {
        var withImage = 0
        var previewCached = 0
        var fullCached = 0
        var pending: [RecipeImageCachePendingEntry] = []

        for entry in entries {
            guard let imageUrl = entry.imageUrl, !imageUrl.isEmpty else { continue }
            withImage += 1

            let hasPreview = isVariantCached(
                recipeId: entry.id,
                imageUrl: imageUrl,
                variant: .preview
            )
            let hasFull = isVariantCached(
                recipeId: entry.id,
                imageUrl: imageUrl,
                variant: .full
            )

            if hasPreview { previewCached += 1 }
            if hasFull { fullCached += 1 }

            if !hasPreview || !hasFull {
                pending.append(
                    RecipeImageCachePendingEntry(
                        id: entry.id,
                        name: entry.name,
                        missingPreview: !hasPreview,
                        missingFull: !hasFull
                    )
                )
            }
        }

        return RecipeImageCacheStatus(
            recipesWithImage: withImage,
            previewCached: previewCached,
            fullCached: fullCached,
            isDownloading: isPrefetching,
            downloadCompleted: prefetchCompleted,
            downloadTotal: prefetchTotal,
            pendingEntries: pending
        )
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

        if isVariantCached(recipeId: recipeId, imageUrl: imageUrl, variant: variant) {
            return RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: variant)
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

        await postCacheStatusChanged()

        guard allowNetwork else { return }

        let candidates = entries.filter { entry in
            guard let url = entry.imageUrl, !url.isEmpty else { return false }
            return true
        }
        guard !candidates.isEmpty else { return }

        let needsPreview = candidates.filter { entry in
            guard let imageUrl = entry.imageUrl else { return false }
            return !isVariantCached(recipeId: entry.id, imageUrl: imageUrl, variant: .preview)
        }
        let needsFull = candidates.filter { entry in
            guard let imageUrl = entry.imageUrl else { return false }
            return !isVariantCached(recipeId: entry.id, imageUrl: imageUrl, variant: .full)
        }
        guard !needsPreview.isEmpty || !needsFull.isEmpty else {
            await postCacheStatusChanged(immediate: true)
            return
        }

        isPrefetching = true
        prefetchCompleted = 0
        prefetchTotal = candidates.count
        await postPrefetchUpdate()

        // Phase 1: all list thumbnails first (visible UX wins).
        await runPrefetchPool(entries: needsPreview) { entry in
            await self.prefetchVariant(entry, variant: .preview)
        }

        // Phase 2: full images for offline detail (parallel, do not block previews).
        await runPrefetchPool(entries: needsFull) { entry in
            await self.prefetchVariant(entry, variant: .full)
            await self.recordPrefetchRecipeCompleted()
        }

        isPrefetching = false
        prefetchCompleted = prefetchTotal
        await postPrefetchUpdate()
        await postCacheStatusChanged(immediate: true)
    }

    func prefetchFull(recipeId: String, imageUrl: String?, allowNetwork: Bool) async {
        guard allowNetwork else { return }
        _ = await ensureCached(
            recipeId: recipeId,
            imageUrl: imageUrl,
            variant: .full,
            allowNetwork: true
        )
        await postCacheStatusChanged()
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

    private func isVariantCached(
        recipeId: String,
        imageUrl: String,
        variant: CachedImageVariant
    ) -> Bool {
        let version = RecipeImageVersion.token(from: imageUrl)
        guard RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: variant) != nil else {
            return false
        }
        return storedVersion(recipeId: recipeId, variant: variant) == version
    }

    private func runPrefetchPool(
        entries: [CollectionEntry],
        work: @escaping @Sendable (CollectionEntry) async -> Void
    ) async {
        guard !entries.isEmpty else { return }
        var index = 0
        await withTaskGroup(of: Void.self) { group in
            let initial = min(prefetchConcurrency, entries.count)
            while index < initial {
                let entry = entries[index]
                index += 1
                group.addTask { await work(entry) }
            }

            for await _ in group {
                guard index < entries.count else { continue }
                let entry = entries[index]
                index += 1
                group.addTask { await work(entry) }
            }
        }
    }

    private func recordPrefetchRecipeCompleted() async {
        prefetchCompleted += 1
        await postPrefetchUpdate()
    }

    private func prefetchVariant(_ entry: CollectionEntry, variant: CachedImageVariant) async {
        guard let imageUrl = entry.imageUrl, !imageUrl.isEmpty else { return }
        guard !isVariantCached(recipeId: entry.id, imageUrl: imageUrl, variant: variant) else { return }
        _ = await ensureCached(
            recipeId: entry.id,
            imageUrl: imageUrl,
            variant: variant,
            allowNetwork: true
        )
    }

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
        guard let remoteURL = APIClient.shared.recipeImageURL(
            id: recipeId,
            preview: variant == .preview,
            version: version
        ) else {
            return nil
        }

        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: remoteURL,
            etag: storedEtag(recipeId: recipeId, variant: variant),
            lastModified: storedLastModified(recipeId: recipeId, variant: variant)
        )

        do {
            let result = try await ImageCacheService.shared.fetchAndCache(
                recipeId: recipeId,
                variant: variant,
                request: request
            )
            storeMetadata(
                recipeId: recipeId,
                variant: variant,
                version: version,
                etag: result.etag,
                lastModified: result.lastModified
            )
            await notifyCached(recipeId: recipeId, variant: variant)
            await postCacheStatusChanged()
            return result.localURL
        } catch {
            return await ImageCacheService.shared.cachedImageURL(recipeId: recipeId, variant: variant)
        }
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

    private func postPrefetchUpdate() async {
        let completed = prefetchCompleted
        let total = prefetchTotal
        let isActive = isPrefetching
        await MainActor.run {
            NotificationCenter.default.post(
                name: .recipeImagePrefetchDidUpdate,
                object: nil,
                userInfo: [
                    "completed": completed,
                    "total": total,
                    "isActive": isActive,
                ]
            )
        }
    }

    private func postCacheStatusChanged(immediate: Bool = false) async {
        cacheStatusNotifyTask?.cancel()
        if immediate {
            await MainActor.run {
                NotificationCenter.default.post(name: .recipeImageCacheStatusDidChange, object: nil)
            }
            return
        }
        cacheStatusNotifyTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                NotificationCenter.default.post(name: .recipeImageCacheStatusDidChange, object: nil)
            }
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