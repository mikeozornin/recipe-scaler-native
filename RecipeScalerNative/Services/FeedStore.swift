//
//  FeedStore.swift
//  RecipeScalerNative
//
//  Spec 072 — in-memory personal feed with keyset pagination.
//
//  Page 1 success = «прочитано»: the store clears the badge store optimistically
//  and echoes `POST /feed/seen { seen_at: snapshot_at }` with the server
//  snapshot from the response. A failed load never sends `seen` — the server
//  marker stays put and the dot returns on the next badge poll (web parity).
//  The snapshot echo is skipped when an older server omitted `snapshot_at`
//  (client clocks are untrusted; review finding #9 on the web client).
//
//  Pagination uses a single-flight guard; a failed page load surfaces
//  `pageError` for the inline retry (auto-retry stays off until the user
//  retries, web parity).
//

import Foundation
import RecipeScalerCore

@MainActor
@Observable
final class FeedStore {
    private(set) var items: [FeedEntryDTO] = []

    private(set) var isLoadingFirstPage = false

    /// Cursor of the last loaded page; `nil` when the feed is exhausted.
    private(set) var nextCursor: String?

    private(set) var isAppendingPage = false

    /// Set when a cursor page fails; the list stays usable and the view shows
    /// an inline retry until this is cleared (successful page or refresh).
    private(set) var pageError = false

    /// Server `has_follows` from page 1 (spec 072 wire contract). `false`
    /// drives the «нет подписок» empty state; `nil` = older server, unknown.
    private(set) var hasFollows: Bool?

    /// Seen-marker cutoff for recomputing `isNew` on cursor pages: after the
    /// page-1 seen echo the server flag is false for the whole backlog, so the
    /// client compares `published_at` against the page-1 cutoff instead.
    /// Falls back to `snapshotAt` (page 1 was queried BEFORE the echo moved
    /// the marker, so it bounds the same set of entries).
    private(set) var lastSeenCutoff: String?

    private var badgeStore: FeedBadgeStore?

    /// Bumped on logout so in-flight page loads / seen-echoes are discarded.
    private var refreshEpoch = 0

    func bind(badgeStore: FeedBadgeStore) {
        self.badgeStore = badgeStore
    }

    // MARK: - First page

    func loadFirstPage(api: APIClient = .shared) async {
        guard !isLoadingFirstPage else { return }
        isLoadingFirstPage = true
        refreshEpoch += 1
        let epoch = refreshEpoch
        defer { isLoadingFirstPage = false }

        pageError = false
        do {
            let page = try await FeedAPI.fetchPage(cursor: nil, api: api)
            guard epoch == refreshEpoch else { return }
            items = page.items
            nextCursor = page.nextCursor
            hasFollows = page.hasFollows
            // Web parity: `lastSeenAt ?? snapshotAt` — both bound the entries
            // the server flagged `is_new` on page 1 (query preceded the echo).
            lastSeenCutoff = page.lastSeenAt ?? page.snapshotAt
            await markLoadedSeen(snapshotAt: page.snapshotAt, epoch: epoch, api: api)
        } catch {
            guard epoch == refreshEpoch else { return }
            pageError = true
            AppLog.info(.app, "feed_first_page_failed", data: [
                "reason": String(describing: type(of: error))
            ])
        }
    }

    // MARK: - Cursor pagination

    /// Loads the next page for `cursor` (single-flight). Retrying the exact
    /// failed cursor is allowed because the cursor is opaque and resending it
    /// refetches the same page (web `retryFeedPage`).
    func loadPage(cursor: String, api: APIClient = .shared) async {
        guard !isAppendingPage else { return }
        isAppendingPage = true
        let epoch = refreshEpoch
        defer { isAppendingPage = false }

        do {
            let page = try await FeedAPI.fetchPage(cursor: cursor, api: api)
            guard epoch == refreshEpoch else { return }
            pageError = false
            let known = Set(items.map(\.recipeId))
            items.append(
                contentsOf: page.items
                    .filter { !known.contains($0.recipeId) }
                    .map { Self.withRecomputedNewness($0, cutoff: lastSeenCutoff) }
            )
            nextCursor = page.nextCursor
        } catch {
            guard epoch == refreshEpoch else { return }
            pageError = true
            AppLog.info(.app, "feed_page_failed", data: [
                "reason": String(describing: type(of: error))
            ])
        }
    }

    /// Pull-to-refresh: replace the list with a fresh first page.
    func refresh(api: APIClient = .shared) async {
        await loadFirstPage(api: api)
    }

    // MARK: - Seen marker («прочитано = загружено»)

    /// Optimistically clears the badge, then echoes the server snapshot time.
    /// A missing snapshot skips the echo entirely — never the local clock.
    private func markLoadedSeen(snapshotAt: String?, epoch: Int, api: APIClient) async {
        badgeStore?.markSeenLocally()
        guard let snapshotAt, !snapshotAt.isEmpty else {
            AppLog.info(.app, "feed_seen_skipped_no_snapshot")
            return
        }
        do {
            try await FeedAPI.markSeen(seenAt: snapshotAt, api: api)
        } catch {
            guard epoch == refreshEpoch else { return }
            AppLog.info(.app, "feed_seen_failed", data: [
                "reason": String(describing: type(of: error))
            ])
        }
    }

    /// Reset on logout / account switch (US8): the in-memory feed belongs to
    /// the previous account. The server-side seen marker is untouched.
    func clearForLogout() {
        refreshEpoch += 1
        items = []
        nextCursor = nil
        isLoadingFirstPage = false
        isAppendingPage = false
        pageError = false
        hasFollows = nil
        lastSeenCutoff = nil
        AppLog.info(.app, "feed_store_cleared")
    }

    // MARK: - isNew cutoff (cursor pages)

    /// `published_at` is `ISO8601` with fractional seconds (`String` in the
    /// DTO — `JSONDecoder.dateDecodingStrategy = .iso8601` rejects those).
    /// Both cutoff and entry timestamps come from the same server clock and
    /// the same `toISOString()` format, so lexicographic comparison is a
    /// faithful ordering.
    static func withRecomputedNewness(_ entry: FeedEntryDTO, cutoff: String?) -> FeedEntryDTO {
        guard let cutoff, !cutoff.isEmpty, !entry.isNew else { return entry }
        guard entry.publishedAt > cutoff else { return entry }
        // `FeedEntryDTO` is a struct of lets — rebuild with the recomputed flag.
        return FeedEntryDTO(
            recipeId: entry.recipeId,
            username: entry.username,
            displayName: entry.displayName,
            avatarRef: entry.avatarRef,
            imageRef: entry.imageRef,
            name: entry.name,
            publishedAt: entry.publishedAt,
            isNew: true
        )
    }
}
