//
//  WatchCredentialsBridge.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — WCSessionDelegate on the watch side. Receives `userId`
//  updates published by `RecipeScalerNative/Services/WatchCredentialsBridge`
//  via `transferUserInfo`. Updates `WatchCredentialsStore`, reconfigures
//  APIClient, and triggers a `TimerListView` refresh.
//

import Foundation
import WatchConnectivity
import RecipeScalerCore

final class WatchCredentialsBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCredentialsBridge()

    /// Called when new userId (or NSNull for purge) arrives.
    var onUserIdChange: ((String?) -> Void)?
    /// Called when iPhone signals timer list changed (start/pause/delete on another device).
    var onTimersChanged: (() -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            applyPayload(session.receivedApplicationContext)
        }
    }

    // MARK: - Payload handling

    private func userId(from payload: [String: Any]) -> String? {
        let raw = payload["userId"]
        if let raw, !(raw is NSNull) {
            return raw as? String
        }
        return nil
    }

    private func applyPayload(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }

        if payload.keys.contains("userId") {
            let userId = userId(from: payload)
            WatchCredentialsStore.set(userId)
            APIClient.shared.configure(userId: userId)
            onUserIdChange?(userId)
        }

        if payload["timersChangedAt"] != nil {
            onTimersChanged?()
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        applyPayload(session.receivedApplicationContext)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        applyPayload(applicationContext)
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        applyPayload(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        applyPayload(session.receivedApplicationContext)
    }
}
