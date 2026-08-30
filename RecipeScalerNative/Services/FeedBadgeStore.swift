//
//  FeedBadgeStore.swift
//  RecipeScalerNative
//
//  Spec 072 — red-dot state for the Discover tab and the «Моя лента» segment.
//
//  Pattern: `SystemBannerStore` (061). `refresh()` polls nothing — it is called
//  once per session from `AppContainer.bootstrap` (after SystemBannerStore) and
//  again on Discover mount. The store never sends `POST /feed/seen` itself:
//  the server marker is owned by `FeedStore`, which clears this state
//  optimistically after a successful first page («прочитано = загружено»).
//

import Foundation
import RecipeScalerCore

@MainActor
@Observable
final class FeedBadgeStore {
    private(set) var hasNew = false

    /// Bumped on logout so in-flight badge fetches are discarded.
    private var refreshEpoch = 0

    func refresh(api: APIClient = .shared) async {
        let epoch = refreshEpoch
        do {
            let badge = try await FeedAPI.fetchBadge(api: api)
            guard epoch == refreshEpoch else { return }
            hasNew = badge.hasNew
        } catch {
            guard epoch == refreshEpoch else { return }
            AppLog.info(.app, "feed_badge_refresh_failed", data: [
                "reason": String(describing: type(of: error))
            ])
        }
    }

    /// Local optimistic clearing after a successful first feed page. Idempotent;
    /// the next `badge` poll re-syncs with the server (a failed `seen` echo
    /// brings the dot back on the next app start / Discover mount).
    ///
    /// Bumps the epoch so any badge fetch started *before* this clearing is
    /// discarded on completion — «гашение сильнее любого in-flight badge-ответа»
    /// (spec 072; same mechanics as `clearForLogout`).
    func markSeenLocally() {
        refreshEpoch += 1
        hasNew = false
    }

    /// Reset on logout / account switch (US8). Bumps the epoch so a stale
    /// badge response cannot restore the previous account's dot.
    func clearForLogout() {
        refreshEpoch += 1
        hasNew = false
        AppLog.info(.app, "feed_badge_cleared")
    }
}
