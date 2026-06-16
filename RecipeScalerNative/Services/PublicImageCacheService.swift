//
//  PublicImageCacheService.swift
//  RecipeScalerNative
//

import Foundation

struct PublicCachedImageResult {
    let localURL: URL
    let etag: String?
    let lastModified: String?
    let statusCode: Int
}

/// Disk cache for public URLs (Discover recipes, avatars). Stored in Caches — ephemeral.
actor PublicImageCacheService {
    static let shared = PublicImageCacheService()

    private static let maxCacheBytes = 150 * 1024 * 1024

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private var inFlight = Set<String>()

    private init() {}

    func cachedFileURL(for url: URL) -> URL? {
        PublicImageDiskCache.existingFileURL(for: url)
    }

    func ensureCached(url: URL, allowNetwork: Bool) async -> URL? {
        if let existing = PublicImageDiskCache.existingFileURL(for: url) {
            if allowNetwork {
                _ = try? await fetchAndCache(url: url)
            }
            return existing
        }
        guard allowNetwork else { return nil }
        return try? await fetchAndCache(url: url).localURL
    }

    func fetchAndCache(url: URL) async throws -> PublicCachedImageResult {
        let key = PublicImageDiskCache.cacheKey(for: url)
        if inFlight.contains(key) {
            return try await waitForInFlight(key: key, url: url)
        }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        return try await performFetch(url: url, key: key)
    }

    private func waitForInFlight(key: String, url: URL) async throws -> PublicCachedImageResult {
        if let existing = PublicImageDiskCache.existingFileURL(for: url) {
            return PublicCachedImageResult(
                localURL: existing,
                etag: storedEtag(for: key),
                lastModified: storedLastModified(for: key),
                statusCode: 200
            )
        }
        for _ in 0 ..< 100 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if let existing = PublicImageDiskCache.existingFileURL(for: url) {
                return PublicCachedImageResult(
                    localURL: existing,
                    etag: storedEtag(for: key),
                    lastModified: storedLastModified(for: key),
                    statusCode: 200
                )
            }
            if !inFlight.contains(key) {
                return try await fetchAndCache(url: url)
            }
        }
        throw URLError(.timedOut)
    }

    private func performFetch(url: URL, key: String) async throws -> PublicCachedImageResult {
        let localURL = PublicImageDiskCache.fileURL(for: url)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = storedEtag(for: key), !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        } else if let lastModified = storedLastModified(for: key), !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

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
                var retry = request
                retry.setValue(nil, forHTTPHeaderField: "If-None-Match")
                retry.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
                return try await performFetch(url: url, key: key)
            }
            storeMetadata(
                key: key,
                etag: responseEtag,
                lastModified: responseLastModified
            )
            return PublicCachedImageResult(
                localURL: localURL,
                etag: responseEtag,
                lastModified: responseLastModified,
                statusCode: statusCode
            )
        }

        guard (200 ... 299).contains(statusCode) else {
            throw URLError(.badServerResponse)
        }

        try ensureBaseDirectoryExists()
        try data.write(to: localURL, options: .atomic)
        storeMetadata(key: key, etag: responseEtag, lastModified: responseLastModified)
        try enforceSizeLimit()

        return PublicCachedImageResult(
            localURL: localURL,
            etag: responseEtag,
            lastModified: responseLastModified,
            statusCode: statusCode
        )
    }

    // MARK: - Private

    private func ensureBaseDirectoryExists() throws {
        let folderURL = PublicImageDiskCache.baseDirectoryURL
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }

    private func storedEtag(for key: String) -> String? {
        defaults.string(forKey: etagKey(for: key))
    }

    private func storedLastModified(for key: String) -> String? {
        defaults.string(forKey: lastModifiedKey(for: key))
    }

    private func storeMetadata(key: String, etag: String?, lastModified: String?) {
        if let etag, !etag.isEmpty {
            defaults.set(etag, forKey: etagKey(for: key))
        }
        if let lastModified, !lastModified.isEmpty {
            defaults.set(lastModified, forKey: lastModifiedKey(for: key))
        }
    }

    private func etagKey(for key: String) -> String {
        "publicImage.\(key).etag"
    }

    private func lastModifiedKey(for key: String) -> String {
        "publicImage.\(key).lastModified"
    }

    private func enforceSizeLimit() throws {
        let folderURL = PublicImageDiskCache.baseDirectoryURL
        guard fileManager.fileExists(atPath: folderURL.path) else { return }

        let files = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var entries: [(url: URL, date: Date, size: Int)] = []
        var totalSize = 0
        for fileURL in files {
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = values.fileSize ?? 0
            totalSize += size
            entries.append((fileURL, values.contentModificationDate ?? .distantPast, size))
        }

        guard totalSize > Self.maxCacheBytes else { return }

        entries.sort { $0.date < $1.date }
        var remaining = totalSize
        for entry in entries {
            guard remaining > Self.maxCacheBytes else { break }
            try? fileManager.removeItem(at: entry.url)
            let key = entry.url.deletingPathExtension().lastPathComponent
            defaults.removeObject(forKey: etagKey(for: key))
            defaults.removeObject(forKey: lastModifiedKey(for: key))
            remaining -= entry.size
        }
    }
}
