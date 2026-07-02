//
//  WatchCredentialsBridge.swift
//  RecipeScalerNative
//
//  Spec 039 — watchOS Timers: iPhone-side WCSessionDelegate that publishes
//  `userId` and `device_token` to paired Apple Watch(es) via `transferUserInfo`.
//  Spec 041 — payload version 2 includes bearer token for watch API calls.
//

import Foundation
import WatchConnectivity
import RecipeScalerCore

final class WatchCredentialsBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCredentialsBridge()

    private static let payloadVersion = 2

    func activate() {
        guard WCSession.isSupported() else {
            AppLog.info(.sync, "watch_bridge_activate_unsupported")
            return
        }
        let session = WCSession.default
        session.delegate = self
        AppLog.info(.sync, "watch_bridge_activate", data: [
            "state": "\(session.activationState.rawValue)",
            "paired": "\(session.isPaired)",
            "watchAppInstalled": "\(session.isWatchAppInstalled)",
        ])
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Publish credentials after login / register / session restore.
    func publish(userId: String, token: String?) {
        publishPayload(userId: userId, token: token)
    }

    /// Backward-compatible entry when only userId is known (legacy callers).
    func publish(userId: String) {
        publish(userId: userId, token: SharedAuthStore.token)
    }

    private func publishPayload(userId: String, token: String?) {
        guard WCSession.isSupported() else {
            AppLog.info(.sync, "watch_bridge_publish_unsupported", data: ["userId": userId])
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            AppLog.info(.sync, "watch_bridge_publish_not_activated", data: [
                "userId": userId,
                "state": "\(session.activationState.rawValue)",
            ])
            return
        }
        AppLog.info(.sync, "watch_bridge_publish", data: [
            "userId": userId,
            "hasToken": "\(token != nil)",
            "paired": "\(session.isPaired)",
            "watchAppInstalled": "\(session.isWatchAppInstalled)",
        ])
        let payload = credentialsPayload(userId: userId, token: token)
        session.transferUserInfo(payload)
        publishApplicationContext(payload, session: session)
    }

    /// Tell the watch to refresh its timer list (new/pause/delete on iPhone or web).
    func publishTimersChanged() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var payload: [String: Any] = [
            "timersChangedAt": Int64(Date().timeIntervalSince1970 * 1000),
            "version": Self.payloadVersion,
        ]
        if let userId = SharedAuthStore.userId {
            payload["userId"] = userId
        }
        if let token = SharedAuthStore.token {
            payload["token"] = token
        }
        session.transferUserInfo(payload)
        publishApplicationContext(payload, session: session)
    }

    /// Tell the watch to purge stored credentials (logout).
    func purge() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        AppLog.info(.sync, "watch_bridge_purge")
        let payload: [String: Any] = [
            "userId": NSNull(),
            "token": NSNull(),
            "version": Self.payloadVersion,
        ]
        session.transferUserInfo(payload)
        publishApplicationContext(payload, session: session)
    }

    private func credentialsPayload(userId: String, token: String?) -> [String: Any] {
        var payload: [String: Any] = [
            "userId": userId,
            "version": Self.payloadVersion,
        ]
        if let token, !token.isEmpty {
            payload["token"] = token
        }
        return payload
    }

    private func publishApplicationContext(_ payload: [String: Any], session: WCSession) {
        do {
            try session.updateApplicationContext(payload)
        } catch {
            AppLog.info(.sync, "watch_bridge_context_failed", data: [
                "error": error.localizedDescription,
            ])
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        AppLog.info(.sync, "watch_bridge_activated", data: [
            "state": "\(activationState.rawValue)",
            "error": error.map { $0.localizedDescription } ?? "nil",
            "paired": "\(session.isPaired)",
            "watchAppInstalled": "\(session.isWatchAppInstalled)",
        ])
        #if os(iOS)
        if activationState == .activated {
            republishStoredCredentialsIfReady(session)
        }
        #endif
    }

    #if os(iOS)
    private func republishStoredCredentialsIfReady(_ session: WCSession) {
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled,
              let userId = SharedAuthStore.userId else { return }
        publish(userId: userId, token: SharedAuthStore.token)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        republishStoredCredentialsIfReady(session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        republishStoredCredentialsIfReady(session)
    }
    #endif
}