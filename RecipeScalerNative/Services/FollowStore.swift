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

    func refresh(username: String, api: APIClient = .shared) async {
        activeUsername = username
        let requestedUsername = username
        do {
            let fetched = try await FollowAPI.fetchStatus(username: requestedUsername, api: api)
            guard activeUsername == requestedUsername else { return }
            // A status response that was in flight while an optimistic mutation
            // for the same profile started must not clobber it — the mutation
            // applies (or rolls back) its own state on completion.
            guard !isFollowingPending else { return }
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
        defer { isFollowingPending = false }

        let previous = optimistic(self)
        let requestedUsername = activeUsername
        do {
            try await perform()
            return true
        } catch {
            // Roll back only when the same profile is still active: a failure
            // for a previous profile must not overwrite the newer profile's
            // freshly refreshed state (same stale-guard as `refresh`).
            if activeUsername == requestedUsername {
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
        isFollowingPending = false
        lastError = nil
        AppLog.info(.app, "follow_store_cleared")
    }
}
