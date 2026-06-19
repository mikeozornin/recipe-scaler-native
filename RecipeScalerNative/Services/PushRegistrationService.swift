//
//  PushRegistrationService.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

@MainActor
final class PushRegistrationService {
    /// Shim: returns `AppContainer.shared.pushRegistration` when the container is
    /// constructed, otherwise lazily instantiates a stand-alone service backed by
    /// `AuthService.shared`. This keeps AppIntents / non-SwiftUI call sites working
    /// during the staged DI migration (review #27).
    static var shared: PushRegistrationService {
        if let container = AppContainer.shared {
            return container.pushRegistration
        }
        return Standalone
    }

    private static let Standalone = PushRegistrationService(auth: AuthService.shared)

    private let auth: AuthService
    private let tokenKey = "apnsDeviceToken"
    private struct VoidData: Decodable {}

    init(auth: AuthService) {
        self.auth = auth
    }

    /// Called from AppDelegate after APNs issues a device token.
    func register(apnsToken: String) async {
        UserDefaults.standard.set(apnsToken, forKey: tokenKey)
        guard auth.isAuthenticated else { return }
        await upload(token: apnsToken)
    }

    /// Called after authentication completes to upload any cached token.
    func registerIfNeeded() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              auth.isAuthenticated else { return }
        await upload(token: token)
    }

    private func upload(token: String) async {
        struct Body: Encodable {
            let token: String
            let device_id: String
        }
        let body = Body(token: token, device_id: TimerSyncService.storedDeviceId())
        do {
            let _: APIResponse<VoidData> = try await APIClient.shared.requestJSON(
                path: "/api/push/apns-register",
                method: "POST",
                body: body
            )
            AppLog.info(.push, "Device token registered")
        } catch {
            AppLog.error(.push, "Token registration failed: \(error.localizedDescription)")
        }
    }
}
