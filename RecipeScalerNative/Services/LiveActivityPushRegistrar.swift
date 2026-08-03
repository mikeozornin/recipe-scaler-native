//
//  LiveActivityPushRegistrar.swift
//  RecipeScalerNative
//
//  Spec 058 — register / unregister ActivityKit push tokens with the server.
//
//  Pure injected dependency of `TimerLiveActivityCoordinator` — no `.shared`
//  shim by design. Spec 058 has no AppIntent / extension / pre-bootstrap call
//  site that would need it, and adding one would violate the composition-root
//  rule (`AppContainer.swift:8-9` — "no hidden cross-singleton wiring").
//

import Foundation
import RecipeScalerCore

/// Abstraction the coordinator depends on so unit tests can inject a stub
/// without touching ActivityKit or the real HTTP path. Production
/// implementation: `LiveActivityPushRegistrar`.
@MainActor
protocol LiveActivityPushRegistering {
    func hasCachedToken(timerId: String) -> Bool
    func clearAllCachedTokens()
    @discardableResult
    func register(timerId: String, tokenHex: String) async -> Bool
    func unregister(timerId: String) async
}

@MainActor
final class LiveActivityPushRegistrar: LiveActivityPushRegistering {
    private struct VoidData: Decodable {}
    private let lastTokenDefaultsPrefix = "liveActivityPushToken."

    init() {}

    /// Whether we already persisted a successful registration for this timer.
    func hasCachedToken(timerId: String) -> Bool {
        guard !timerId.isEmpty else { return false }
        return UserDefaults.standard.string(forKey: lastTokenDefaultsPrefix + timerId) != nil
    }

    /// Wipe every cached `liveActivityPushToken.*` entry. Called from
    /// `TimerLiveActivityCoordinator.clearForLogout()` (via `AppContainer.stopForLogout`
    /// and `AuthService.wipeLocalSession`) so that a partial `endAll()` failure
    /// (or a `register` that succeeded without the activity ever being tracked in
    /// `activityByTimerId`) cannot leak the previous user's tokens across an
    /// account switch. Mirrors `FeatureAdoptionStore.clearForLogout()`.
    func clearAllCachedTokens() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(lastTokenDefaultsPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Upload an ActivityKit push token for `timerId`.
    /// - Returns: `true` when the token is registered (or was already cached as identical);
    ///   `false` on network/server failure so the caller can resubscribe later.
    @discardableResult
    func register(timerId: String, tokenHex: String) async -> Bool {
        guard !timerId.isEmpty, !tokenHex.isEmpty else { return false }
        let key = lastTokenDefaultsPrefix + timerId
        let deviceId = TimerSyncService.storedDeviceId()
        if UserDefaults.standard.string(forKey: key) == tokenHex {
            return true
        }

        struct Body: Encodable {
            let timer_id: String
            let token: String
            let device_id: String
        }
        let body = Body(
            timer_id: timerId,
            token: tokenHex,
            device_id: deviceId
        )
        do {
            let _: APIResponse<VoidData> = try await APIClient.shared.requestJSON(
                path: "/api/push/apns-register-liveactivity",
                method: "POST",
                body: body
            )
            UserDefaults.standard.set(tokenHex, forKey: key)
            AppLog.info(.push, "live_activity_token_registered", data: [
                "timerId": timerId,
                "tokenPrefix": String(tokenHex.prefix(8))
            ])
            return true
        } catch {
            AppLog.error(.push, "live_activity_token_register_failed", data: [
                "timerId": timerId,
                "error": error.localizedDescription
            ])
            return false
        }
    }

    /// Best-effort unregister when a Live Activity ends locally.
    func unregister(timerId: String) async {
        guard !timerId.isEmpty else { return }
        let key = lastTokenDefaultsPrefix + timerId
        UserDefaults.standard.removeObject(forKey: key)

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "timer_id", value: timerId),
            URLQueryItem(name: "device_id", value: TimerSyncService.storedDeviceId())
        ]
        let query = components.percentEncodedQuery ?? ""
        let path = "/api/push/apns-register-liveactivity?\(query)"
        do {
            let _: APIResponse<VoidData> = try await APIClient.shared.requestJSON(
                path: path,
                method: "DELETE"
            )
            AppLog.info(.push, "live_activity_token_unregistered", data: ["timerId": timerId])
        } catch {
            // Endpoint may not exist yet while server 058 is in flight — log and move on.
            AppLog.notice(.push, "live_activity_token_unregister_failed", data: [
                "timerId": timerId,
                "error": error.localizedDescription
            ])
        }
    }
}
