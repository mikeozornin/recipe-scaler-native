//
//  MarkdownCache.swift
//  RecipeScalerNative
//
//  Memoized `[AssistantMarkdownBlock]` parse results for `AssistantMarkdownText`.
//
//  Re-rendering a chat bubble during scroll used to re-run
//  `AssistantMarkdownRenderer.blocks(from:)` on every pass. The cache keys parsed
//  block lists by source string, so subsequent renders are O(1) lookups.
//

import Foundation

/// Cache entry wrapping parsed blocks so they can be stored in `NSCache`
/// (which requires a class).
final class MarkdownCacheEntry: NSObject {
    let blocks: [AssistantMarkdownBlock]

    init(blocks: [AssistantMarkdownBlock]) {
        self.blocks = blocks
    }
}

/// Shared, bounded cache for assistant markdown blocks.
///
/// `NSCache` is thread-safe and evicts entries under pressure according to
/// `countLimit` / `totalCostLimit`. Keyed by the raw markdown source — identical
/// strings (e.g. the same message re-rendered during scroll) hit the cache.
enum MarkdownCache {
    static let shared = MarkdownCacheStorage()

    /// Returns cached blocks for `content`, parsing-and-storing on miss.
    /// Identical to calling `AssistantMarkdownRenderer.blocks(from:)` directly,
    /// but amortized across re-renders.
    static func blocks(for content: String) -> [AssistantMarkdownBlock] {
        shared.blocks(for: content)
    }
}

final class MarkdownCacheStorage {
    private let cache: NSCache<NSString, MarkdownCacheEntry> = {
        let cache = NSCache<NSString, MarkdownCacheEntry>()
        cache.countLimit = 64
        cache.totalCostLimit = 5_000_000 // ~5 MB of source text
        return cache
    }()

    func blocks(for content: String) -> [AssistantMarkdownBlock] {
        let key = content as NSString
        if let cached = cache.object(forKey: key) {
            return cached.blocks
        }
        let parsed = AssistantMarkdownRenderer.blocks(from: content)
        cache.setObject(
            MarkdownCacheEntry(blocks: parsed),
            forKey: key,
            cost: content.utf8.count
        )
        return parsed
    }
}
