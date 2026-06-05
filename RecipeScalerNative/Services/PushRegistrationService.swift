//
//  PushRegistrationService.swift
//  RecipeScalerNative
//

import Foundation

@MainActor
final class PushRegistrationService {
    static let shared = PushRegistrationService()

    private let tokenKey = "apnsDeviceToken"
    private struct VoidData: Decodable {}

    private init() {}

    /// Called from AppDelegate after APNs issues a device token.
    func register(apnsToken: String) async {
        UserDefaults.standard.set(apnsToken, forKey: tokenKey)
        guard AuthService.shared.isAuthenticated else { return }
        await upload(token: apnsToken)
    }

    /// Called after authentication completes to upload any cached token.
    func registerIfNeeded() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              AuthService.shared.isAuthenticated else { return }
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
            print("[APNs] Device token registered")
        } catch {
            print("[APNs] Token registration failed: \(error.localizedDescription)")
        }
    }
}
