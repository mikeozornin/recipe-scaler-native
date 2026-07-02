//
//  WatchCredentialsBridge.swift
//  RecipeScalerNativeWatch Watch App
//
//  Receives `userId` and optional `device_token` from iPhone (spec 039 / 041).
//

import Foundation
import WatchConnectivity
import RecipeScalerCore

final class WatchCredentialsBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCredentialsBridge()

    var onUserIdChange: ((String?) -> Void)?
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

    private func optionalString(from payload: [String: Any], key: String) -> String? {
        let raw = payload[key]
        if let raw, !(raw is NSNull) {
            return raw as? String
        }
        return nil
    }

    private func applyPayload(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }

        if payload.keys.contains("userId") {
            let userId = optionalString(from: payload, key: "userId")
            let token = optionalString(from: payload, key: "token")
            if let userId, !userId.isEmpty {
                WatchCredentialsStore.set(userId, token: token)
                configureAPIClient(userId: userId, token: token)
            } else {
                WatchCredentialsStore.clear()
                deconfigureAPIClient()
            }
            onUserIdChange?(userId)
        }

        if payload["timersChangedAt"] != nil {
            onTimersChanged?()
        }
    }

    private func configureAPIClient(userId: String, token: String?) {
        if let token, !token.isEmpty {
            APIClient.shared.configure(authToken: token)
            APIClient.shared.configure(userId: userId)
        } else {
            APIClient.shared.configure(authToken: nil)
            APIClient.shared.configure(userId: userId)
        }
    }

    private func deconfigureAPIClient() {
        APIClient.shared.configure(authToken: nil)
        APIClient.shared.configure(userId: nil)
    }

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