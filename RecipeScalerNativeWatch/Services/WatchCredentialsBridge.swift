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

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // No-op: we just need to receive `didReceiveUserInfo`. If the user
        // is already authenticated and `transferUserInfo` was queued while
        // the watch was off, the system will replay it here.
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        let raw = userInfo["userId"]
        let userId: String?
        if let raw, !(raw is NSNull) {
            userId = raw as? String
        } else {
            userId = nil
        }

        WatchCredentialsStore.set(userId)

        // Pass the userId through unconditionally — `nil` is the whole point
        // of the optional signature, and clears the stale `x-user-id` header
        // so any in-flight background fetch can no longer leak the previous
        // user's identity (review M4).
        APIClient.shared.configure(userId: userId)

        onUserIdChange?(userId)
    }
}
