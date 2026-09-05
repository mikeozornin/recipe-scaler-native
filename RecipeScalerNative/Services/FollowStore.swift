//
//  FollowStore.swift
//  RecipeScalerNative
//
//  Spec 072 — follow status for the profile currently on screen.
//
//  Pattern: `SystemBannerStore` (061). The store holds the relationship state
//  (`following`, `pushOptIn`) for the requested `username`. `refresh(username:)`
//  captures the username before the await and applies the result only if the
//  same profile is still active (stale-guard), so a slow response for a
//  previous profile cannot overwrite the current one.
//
//  Mutations are optimistic: `follow` / `unfollow` / `setPushOptIn` update the
//  in-memory state first and roll it back on failure (US6 — state unchanged,
//  localized server dot-key error shown by the view layer).
//

import Foundation
import RecipeScalerCore

@MainActor
@Observable
final class FollowStore {
    private(set) var status: FollowStatusDTO?

    private(set) var isFollowingPending = false

    private var activeUsername: String?

    /// Monotonic counter bumped on every `refresh()` entry — lets the
    /// mutation completion tell a mid-mutation refresh (issued after the
    /// mutation started → fresher server truth, apply it) from a
    /// pre-mutation refresh (issued before → stale snapshot, must not revert
    /// the optimistic state; invariant of
    /// `test_refresh_does_not_clobber_pending_optimistic_follow`).
    private var refreshEpoch = 0

    /// Review 2026.09.04 №13: a status response that landed while an
    /// optimistic mutation was in flight used to be discarded wholesale —
    /// the follow state of profile A then stayed on screen for profile B.
    /// The response is now parked (with its username + epoch) and applied by
    /// the mutation's completion when it is the freshest server truth.
    private var deferredStatus: (username: String, status: FollowStatusDTO, epoch: Int)?

    func refresh(username: String, api: APIClient = .shared) async {
        activeUsername = username
        refreshEpoch += 1
        let requestedUsername = username
        let requestedEpoch = refreshEpoch
        do {
            let fetched = try await FollowAPI.fetchStatus(username: requestedUsername, api: api)
            guard activeUsername == requestedUsername else { return }
            // A status response that was in flight while an optimistic mutation
            // for the same profile started must not clobber it — park it; the
            // mutation applies (or rolls back) its own state, then adopts the
            // parked response when it is the freshest server truth.
            guard !isFollowingPending else {
                deferredStatus = (requestedUsername, fetched, requestedEpoch)
                return
            }
            status = fetched
        } catch {
            guard activeUsername == requestedUsername else { return }
            AppLog.info(.app, "follow_status_refresh_failed", data: [
                "username_hash": Self.pseudonymized(requestedUsername),
                "reason": String(describing: type(of: error))
            ])
        }
    }

    /// Optimistic subscribe. Returns `false` on failure; state rolls back and
    /// the error is surfaced via `lastError` for the view layer to present.
    @discardableResult
    func follow(username: String, api: APIClient = .shared) async -> Bool {
        await mutate(username: username, api: api) { store in
            let previous = store.status
            store.status = FollowStatusDTO(following: true, pushOptIn: previous?.pushOptIn ?? false)
            return previous
        } perform: {
            try await FollowAPI.follow(username: username, api: api)
        }
    }

    /// Optimistic unsubscribe. Rolls back on failure.
    @discardableResult
    func unfollow(username: String, api: APIClient = .shared) async -> Bool {
        await mutate(username: username, api: api) { store in
            let previous = store.status
            store.status = FollowStatusDTO(following: false, pushOptIn: false)
            return previous
        } perform: {
            try await FollowAPI.unfollow(username: username, api: api)
        }
    }

    /// Optimistic bell toggle. Requires an active follow server-side
    /// (`follow.not-following` otherwise); rolls back on failure.
    @discardableResult
    func setPushOptIn(
        username: String,
        _ enabled: Bool,
        api: APIClient = .shared
    ) async -> Bool {
        await mutate(username: username, api: api) { store in
            let previous = store.status
            store.status = FollowStatusDTO(following: true, pushOptIn: enabled)
            return previous
        } perform: {
            _ = try await FollowAPI.setPushOptIn(username: username, pushOptIn: enabled, api: api)
        }
    }

    private func mutate(
        username: String,
        api: APIClient,
        optimistic: (FollowStore) -> FollowStatusDTO?,
        perform: () async throws -> Void
    ) async -> Bool {
        guard isFollowingPending == false else { return false }
        isFollowingPending = true
        let mutationStartEpoch = refreshEpoch
        defer {
            isFollowingPending = false
            // Adopt a status response that arrived from the server while this
            // mutation was in flight — but only when its refresh was issued
            // after the mutation started (post-mutation server truth). A
            // pre-mutation refresh response is a stale snapshot and must not
            // revert the optimistic state.
            if let deferred = deferredStatus,
               deferred.epoch > mutationStartEpoch,
               deferred.username == activeUsername {
                status = deferred.status
            }
            deferredStatus = nil
        }

        // Review 2026.09.04 №13: the optimistic write targets the profile
        // currently on screen. A mutation for a different (backgrounded)
        // profile still runs server-side but must not repaint `status`.
        let optimisticApplies = (username == activeUsername)
        let previous = optimisticApplies ? optimistic(self) : status
        let requestedUsername = activeUsername
        do {
            try await perform()
            return true
        } catch {
            // Roll back only when the same profile is still active: a failure
            // for a previous profile must not overwrite the newer profile's
            // freshly refreshed state (same stale-guard as `refresh`).
            if activeUsername == requestedUsername, optimisticApplies {
                status = previous
            }
            lastError = Self.serverCode(of: error)
            AppLog.info(.app, "follow_mutation_failed", data: [
                "username_hash": Self.pseudonymized(username),
                "reason": String(describing: type(of: error))
            ])
            return false
        }
    }

    /// Server dot-key of the last failed mutation (US9), consumed by the UI.
    private(set) var lastError: ServerErrorCode?

    func clearError() {
        lastError = nil
    }

    private static func serverCode(of error: Error) -> ServerErrorCode? {
        guard case APIError.serverError(let code) = error else { return nil }
        return code
    }

    /// Usernames must not leak into logs (privacy parity with web); hash-ish
    /// prefix only, enough to correlate rows within one debug session.
    private static func pseudonymized(_ username: String) -> String {
        String(username.hashValue.description.prefix(8))
    }

    /// Reset on logout / account switch (US8): no relationship state may leak
    /// into the next session's UI.
    func clearForLogout() {
        activeUsername = nil
        status = nil
        deferredStatus = nil
        isFollowingPending = false
        lastError = nil
        AppLog.info(.app, "follow_store_cleared")
    }
}
