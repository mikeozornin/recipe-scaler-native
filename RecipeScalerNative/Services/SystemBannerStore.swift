//
//  SystemBannerStore.swift
//  RecipeScalerNative
//
//  Spec 061 — system banner over the recipe list.
//
//  Holds the currently active banner for the signed-in user. The store is the
//  single source of truth for `SystemBannerView`. Dismissal is persisted on
//  the server (idempotent), so there is no local cache to manage: after
//  `dismiss()` clears the in-memory banner, the next `refresh()` will return
//  `nil` because the server has recorded the dismissal.
//
//  Refresh is invoked exactly once per session from `AppContainer.bootstrap`
//  after `APIClient` is configured (no polling, no `scenePhase` re-fetch).
//  Errors are swallowed — offline / transient failures silently leave
//  `activeBanner` as `nil` and the next app launch will try again.
//
//  `refreshEpoch` guards against a logout race: if `clearForLogout()` runs
//  while a refresh is in flight, the stale fetch must not restore the
//  previous account's banner.
//

import Foundation

@MainActor
@Observable
final class SystemBannerStore {
    /// The active banner the current user has not dismissed. `nil` when:
    /// - there is no active banner, or
    /// - the user has dismissed it, or
    /// - the initial fetch has not completed / failed.
    var activeBanner: SystemBannerDTO?

    private var dismissedBannerIds: Set<UUID> = []

    /// Bumped on logout so in-flight `refresh()` results are discarded.
    private var refreshEpoch = 0

    /// Synchronous cache load. No persistent cache is used for the banner
    /// payload itself (it is a single, server-driven row that changes
    /// rarely), so this is currently a no-op. Kept for symmetry with
    /// `FeatureAdoptionStore.loadFromCache()` and to give a stable place
    /// to hang future warm-start logic if needed.
    func loadFromCache() {
        // Intentionally empty — see class docs.
    }

    /// Fetch the active banner from the server. Idempotent; safe to call
    /// multiple times. Network / decoding errors are logged and swallowed
    /// so a flaky network never blocks the recipe list.
    func refresh() async {
        let epoch = refreshEpoch
        do {
            let banner = try await SystemBannerAPI.fetchActive()
            applyFetchedBanner(banner, forEpoch: epoch)
        } catch {
            AppLog.info(.app, "system_banner_refresh_failed", data: [
                "reason": String(describing: type(of: error)),
                "detail": String(describing: error)
            ])
        }
    }

    /// Apply a fetched banner only if `forEpoch` still matches `refreshEpoch`.
    /// Package-visible for unit tests of the logout race without hitting the network.
    func applyFetchedBanner(_ banner: SystemBannerDTO?, forEpoch epoch: Int) {
        guard epoch == refreshEpoch else { return }
        // Filter out banners dismissed this session: the POST is
        // optimistic and the server eventually catches up, but until
        // the next refresh the dismissed id is held in memory.
        if let banner, dismissedBannerIds.contains(banner.id) {
            activeBanner = nil
        } else {
            activeBanner = banner
        }
    }

    /// Optimistically hide the banner and persist the dismissal on the
    /// server. Network failures are logged but do not restore the banner —
    /// the next cold start will re-fetch, and (if the POST truly failed)
    /// the banner will re-appear and the user can dismiss it again.
    func dismiss() async {
        guard let banner = activeBanner else { return }
        let bannerId = banner.id

        activeBanner = nil
        dismissedBannerIds.insert(bannerId)

        do {
            try await SystemBannerAPI.dismiss(bannerId: bannerId)
        } catch {
            AppLog.info(.app, "system_banner_dismiss_failed", data: [
                "banner_id": bannerId.uuidString,
                "reason": String(describing: type(of: error))
            ])
        }
    }

    /// Reset in-memory state on logout / account switch so the next account's
    /// banner does not leak through the previous account's UI. Bumps
    /// `refreshEpoch` so any in-flight refresh is ignored when it completes.
    func clearForLogout() {
        refreshEpoch += 1
        activeBanner = nil
        dismissedBannerIds.removeAll()
        AppLog.info(.app, "system_banner_cleared")
    }
}
