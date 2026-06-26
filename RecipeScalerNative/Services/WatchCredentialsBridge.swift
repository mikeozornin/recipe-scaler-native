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
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Publish `userId` to the watch after a successful login / register.
    func publish(userId: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferUserInfo(["userId": userId])
    }

    /// Tell the watch to purge stored credentials (logout).
    func purge() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // `NSNull()` serializes as JSON null — watch decodes it as `nil`.
        session.transferUserInfo(["userId": NSNull()])
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // No-op: iPhone only publishes; it does not need to receive.
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
