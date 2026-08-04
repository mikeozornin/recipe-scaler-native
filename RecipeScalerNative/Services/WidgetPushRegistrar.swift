//
//  WidgetPushRegistrar.swift
//  RecipeScalerNative
//
//  Spec 030 Phase B2 — AppContainer-owned wrapper around WidgetPushTokenClient
//  with AppLog English event names. No `.shared` shim (composition-root only).
//  WidgetKit `.pushHandler` is not wired on appex DT 17; this registrar is ready
//  for a future token source / cached re-POST (see TimerWidgetPushHandler).
//

import Foundation
import RecipeScalerCore

@MainActor
final class WidgetPushRegistrar {
    init() {}

    var hasCachedToken: Bool {
        !(WidgetPushTokenClient.cachedTokenHex ?? "").isEmpty
    }

    /// Upload a widget push token. Returns `true` on success or cache hit.
    @discardableResult
    func register(tokenHex: String) async -> Bool {
        configureAPIClientFromSharedAuth()
        let deviceId = SharedDeviceId.current()
        let ok = await WidgetPushTokenClient.register(tokenHex: tokenHex, deviceId: deviceId)
        if ok {
            AppLog.info(.push, "widget_push_token_registered", data: [
                "tokenPrefix": String(tokenHex.prefix(8)),
                "deviceId": deviceId
            ])
        } else {
            AppLog.error(.push, "widget_push_token_register_failed", data: [
                "tokenPrefix": String(tokenHex.prefix(8)),
                "deviceId": deviceId
            ])
        }
        return ok
    }

    /// Re-POST a token already written by the widget extension (bootstrap path).
    func registerCachedIfNeeded() async {
        guard let token = WidgetPushTokenClient.cachedTokenHex, !token.isEmpty else { return }
        // Force network even if cache matches — clear then re-register would lose
        // dedup. Instead call register which dedups on identical cache; if the
        // extension already POSTed successfully this is a no-op. If only the
        // cache was written without a successful POST, clear cache first.
        // Extension always POSTs then caches on success, so bootstrap re-register
        // of an identical token short-circuits — good.
        _ = await register(tokenHex: token)
    }

    /// Best-effort DELETE + clear local cache (logout / account wipe).
    func unregister() async {
        configureAPIClientFromSharedAuth()
        let deviceId = SharedDeviceId.current()
        let outcome = await WidgetPushTokenClient.unregister(deviceId: deviceId)
        switch outcome {
        case .success:
            AppLog.info(.push, "widget_push_token_unregistered", data: ["deviceId": deviceId])
        case .unauthorized:
            // Security review critical finding #1: DELETE went out without a
            // valid bearer — orphan `widget_push_tokens` row survives. Surface
            // it so logout ordering regressions are observable in logs.
            AppLog.error(.push, "widget_push_token_unregister_unauthorized", data: ["deviceId": deviceId])
        case .failure:
            AppLog.notice(.push, "widget_push_token_unregister_failed", data: ["deviceId": deviceId])
        }
    }

    /// Wipe cache without hitting the network (already unregistered / offline wipe).
    func clearCachedToken() {
        WidgetPushTokenClient.clearCachedToken()
    }

    private func configureAPIClientFromSharedAuth() {
        if let token = SharedAuthStore.token, !token.isEmpty {
            APIClient.shared.configure(authToken: token)
        }
        if let userId = SharedAuthStore.userId, !userId.isEmpty {
            APIClient.shared.configure(userId: userId)
        }
    }
}
