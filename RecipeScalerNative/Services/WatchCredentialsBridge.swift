//
//  WatchCredentialsBridge.swift
//  RecipeScalerNative
//
//  Spec 039 — watchOS Timers: iPhone-side WCSessionDelegate that publishes
//  `userId` to paired Apple Watch(es) via `transferUserInfo`. One-way
//  outbound only — watch receives via its own delegate.
//
//  `transferUserInfo` is queued and guaranteed to be delivered when the
//  watch is next reachable. We don't need reachability-based messaging.
//

import Foundation
import WatchConnectivity

final class WatchCredentialsBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCredentialsBridge()

    /// Activate the session. Safe to call from `AppDelegate.didFinishLaunching`;
    /// no-op on iPads / Simulators without watch support (`WCSession.isSupported()`).
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

    /// Publish `userId` to the watch after a successful login / register.
    func publish(userId: String) {
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
            "paired": "\(session.isPaired)",
            "watchAppInstalled": "\(session.isWatchAppInstalled)",
        ])
        session.transferUserInfo(["userId": userId])
    }

    /// Tell the watch to purge stored credentials (logout).
    func purge() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        AppLog.info(.sync, "watch_bridge_purge")
        // `NSNull()` serializes as JSON null — watch decodes it as `nil`.
        session.transferUserInfo(["userId": NSNull()])
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
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        // System-managed — no action needed.
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for the next paired watch session.
        session.activate()
    }
    #endif
}
