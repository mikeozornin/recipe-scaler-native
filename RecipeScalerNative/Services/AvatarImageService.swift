import Foundation
import UIKit
import RecipeScalerCore

/// Loads user avatars with auth headers (`x-user-id` / `Bearer`) and keeps them
/// in memory. Replaces the previous direct `APIClient.shared` call in
/// `AuthAvatarImage` — `.shared` is a cross-process IPC shim, not for view code
/// (project `AGENTS.md`).
///
/// `@MainActor` because `UIImage` is non-Sendable and every caller is a SwiftUI
/// view already isolated to the main actor; in-memory cache hits are O(1).
@MainActor
@Observable
final class AvatarImageService {
    private let api: APIClient
    private let cache = NSCache<NSURL, UIImage>()
    /// Dedups parallel fetches for the same URL so two views pointing at one
    /// avatar share a single network round-trip (matches `RecipeImageService.inFlight`).
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(api: APIClient) {
        self.api = api
    }

    /// Returns the cached avatar for `url`, or fetches it on demand.
    /// Cache misses and in-flight dedup are transparent to the caller.
    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if let task = inFlight[url] {
            return await task.value
        }
        let task = Task<UIImage?, Never> { @MainActor [api, cache, url] in
            let request = api.recipeImageDownloadRequest(
                remoteURL: url,
                etag: nil,
                lastModified: nil
            )
            guard let (data, _) = try? await AppURLSession.shared.data(for: request),
                  let image = UIImage(data: data) else {
                return nil as UIImage?
            }
            cache.setObject(image, forKey: url as NSURL)
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return await task.value
    }
}
