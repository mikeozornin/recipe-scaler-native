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
import os
import RecipeScalerCore

final class WatchCredentialsBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCredentialsBridge()

    private let log = OSLog(subsystem: "ru.recipescaler.RecipeScalerNative.watchkitapp", category: "WatchCredentialsBridge")

    /// Called when new userId (or NSNull for purge) arrives.
    var onUserIdChange: ((String?) -> Void)?

    func activate() {
        guard WCSession.isSupported() else {
            os_log("WCSession not supported on this device", log: log, type: .info)
            return
        }
        let session = WCSession.default
        session.delegate = self
        os_log("activate: state=%d", log: log, type: .info, session.activationState.rawValue)
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
        os_log("activationDidCompleteWith: state=%d, error=%{public}@",
               log: log, type: .info,
               activationState.rawValue,
               error.map { $0.localizedDescription } ?? "nil")
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

        os_log("didReceiveUserInfo: userId=%{public}@",
               log: log, type: .info,
               userId ?? "<nil>")

        WatchCredentialsStore.set(userId)

        // Pass the userId through unconditionally — `nil` is the whole point
        // of the optional signature, and clears the stale `x-user-id` header
        // so any in-flight background fetch can no longer leak the previous
        // user's identity (review M4).
        APIClient.shared.configure(userId: userId)

        onUserIdChange?(userId)
    }
}
