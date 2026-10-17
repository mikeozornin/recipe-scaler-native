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
//  A streaming reply changes on every flush, so its prefixes go to a single
//  "latest streaming" slot instead of the shared cache: otherwise one long reply
//  would push every finished message out of the 64-entry cache.
//
//  Rendered `AttributedString`s (inline markdown, headers) are cached per block
//  text, so finished blocks are not re-parsed by `AttributedString(markdown:)`
//  each time their bubble re-renders.
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

/// `NSCache` entry for a rendered block.
final class MarkdownRenderedTextEntry: NSObject {
    let attributed: AttributedString

    init(attributed: AttributedString) {
        self.attributed = attributed
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

    private let inlineCache: NSCache<NSString, MarkdownRenderedTextEntry> = {
        let cache = NSCache<NSString, MarkdownRenderedTextEntry>()
        cache.countLimit = 512
        cache.totalCostLimit = 2_000_000 // ~2 MB of source text
        return cache
    }()

    private let headerCache: NSCache<NSString, MarkdownRenderedTextEntry> = {
        let cache = NSCache<NSString, MarkdownRenderedTextEntry>()
        cache.countLimit = 128
        return cache
    }()

    private let streamingLock = NSLock()
    private var latestStreamingContent: String?
    private var latestStreamingBlocks: [AssistantMarkdownBlock] = []

    func blocks(for content: String) -> [AssistantMarkdownBlock] {
        blocks(for: content, isStreaming: false)
    }

    /// Same result as `AssistantMarkdownRenderer.blocks(from:)`. While a reply is
    /// streaming only its latest text is kept, outside the shared cache.
    func blocks(for content: String, isStreaming: Bool) -> [AssistantMarkdownBlock] {
        let key = content as NSString
        if let cached = cache.object(forKey: key) {
            return cached.blocks
        }
        if isStreaming {
            streamingLock.lock()
            defer { streamingLock.unlock() }
            if latestStreamingContent == content {
                return latestStreamingBlocks
            }
            let parsed = AssistantMarkdownRenderer.blocks(from: content)
            latestStreamingContent = content
            latestStreamingBlocks = parsed
            return parsed
        }
        let parsed = AssistantMarkdownRenderer.blocks(from: content)
        cache.setObject(
            MarkdownCacheEntry(blocks: parsed),
            forKey: key,
            cost: content.utf8.count
        )
        return parsed
    }

    /// `AssistantMarkdownRenderer.inlineAttributedString(from:)`, memoized when
    /// `storesResult` is true (pass false for text that is still streaming).
    func inlineAttributedString(for text: String, storesResult: Bool) -> AttributedString {
        let key = text as NSString
        if let cached = inlineCache.object(forKey: key) {
            return cached.attributed
        }
        let rendered = AssistantMarkdownRenderer.inlineAttributedString(from: text)
        if storesResult {
            inlineCache.setObject(
                MarkdownRenderedTextEntry(attributed: rendered),
                forKey: key,
                cost: text.utf8.count
            )
        }
        return rendered
    }

    /// `AssistantMarkdownRenderer.headerAttributedString(from:level:)`, memoized when
    /// `storesResult` is true.
    func headerAttributedString(for text: String, level: Int, storesResult: Bool) -> AttributedString {
        let key = "\(level)\u{0}\(text)" as NSString
        if let cached = headerCache.object(forKey: key) {
            return cached.attributed
        }
        let rendered = AssistantMarkdownRenderer.headerAttributedString(from: text, level: level)
        if storesResult {
            headerCache.setObject(MarkdownRenderedTextEntry(attributed: rendered), forKey: key)
        }
        return rendered
    }

    #if DEBUG
    func hasCachedBlocks(for content: String) -> Bool {
        cache.object(forKey: content as NSString) != nil
    }

    func hasCachedInlineText(_ text: String) -> Bool {
        inlineCache.object(forKey: text as NSString) != nil
    }
    #endif
}
