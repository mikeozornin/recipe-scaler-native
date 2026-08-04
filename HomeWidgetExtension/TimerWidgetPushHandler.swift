//
//  TimerWidgetPushHandler.swift
//  HomeWidgetExtension
//
//  Spec 030 Phase B2 — WidgetKit push token callback (SDK: iOS 26+).
//
//  NOT wired into `TimerWidget` while HomeWidgetExtension deployment stays at
//  iOS 17: attaching `.pushHandler` changes the opaque `WidgetConfiguration`
//  type and cannot be `#available`-split without raising appex DT to 26.
//  Kept as a reference implementation for a future dual-target / type-erased
//  configuration. Until then, iOS 17–25 rely on silent APNs + Provider fetch
//  (Phases B3/B4); see contracts/widget-push.md.
//

import Foundation
import WidgetKit
import RecipeScalerCore

/// Receives the device-level widget push token and registers it with the server.
///
/// Reserved for a future wire-up when appex can attach `.pushHandler` without
/// raising `IPHONEOS_DEPLOYMENT_TARGET` above 17.
@available(iOS 26.0, *)
struct TimerWidgetPushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let tokenHex = pushInfo.token.map { String(format: "%02x", $0) }.joined()
        guard !tokenHex.isEmpty else { return }

        // Extension process: hydrate APIClient from the shared keychain before POST.
        if let bearer = SharedAuthStore.token, !bearer.isEmpty {
            APIClient.shared.configure(authToken: bearer)
        }
        if let userId = SharedAuthStore.userId, !userId.isEmpty {
            APIClient.shared.configure(userId: userId)
        }

        let deviceId = SharedDeviceId.current()
        Task {
            _ = await WidgetPushTokenClient.register(tokenHex: tokenHex, deviceId: deviceId)
        }
    }
}
