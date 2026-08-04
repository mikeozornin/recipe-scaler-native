//
//  WidgetPushTokenClient.swift
//  RecipeScalerCore
//
//  Spec 030 Phase B2 — HTTP register / unregister for WidgetKit push tokens.
//  Usable from the main app and HomeWidgetExtension (no AppLog dependency).
//

import Foundation

/// Thin HTTP + App Group cache for device-level widget push tokens.
public enum WidgetPushTokenClient {
    private struct VoidData: Decodable {}

    /// Last token observed from WidgetKit (may not yet be registered).
    public static let pendingCacheKey = "widgets.pushToken.pending"

    /// Last token successfully POSTed to the server.
    public static let registeredCacheKey = "widgets.pushToken.registered"

    public static var pendingTokenHex: String? {
        get { AppGroup.userDefaults?.string(forKey: pendingCacheKey) }
        set {
            if let newValue, !newValue.isEmpty {
                AppGroup.userDefaults?.set(newValue, forKey: pendingCacheKey)
            } else {
                AppGroup.userDefaults?.removeObject(forKey: pendingCacheKey)
            }
        }
    }

    public static var registeredTokenHex: String? {
        get { AppGroup.userDefaults?.string(forKey: registeredCacheKey) }
        set {
            if let newValue, !newValue.isEmpty {
                AppGroup.userDefaults?.set(newValue, forKey: registeredCacheKey)
            } else {
                AppGroup.userDefaults?.removeObject(forKey: registeredCacheKey)
            }
        }
    }

    /// Convenience: prefer pending, else registered (bootstrap / diagnostics).
    public static var cachedTokenHex: String? {
        pendingTokenHex ?? registeredTokenHex
    }

    public static func clearCachedToken() {
        pendingTokenHex = nil
        registeredTokenHex = nil
    }

    /// POST `/api/push/apns-register-widget` — UPSERT by (user, device_id).
    /// Dedups when the server already has this exact token registered locally.
    @discardableResult
    public static func register(tokenHex: String, deviceId: String) async -> Bool {
        guard !tokenHex.isEmpty, !deviceId.isEmpty else { return false }
        pendingTokenHex = tokenHex
        if registeredTokenHex == tokenHex {
            return true
        }

        struct Body: Encodable {
            let token: String
            let device_id: String
        }
        do {
            let _: APIResponse<VoidData> = try await APIClient.shared.requestJSON(
                path: "/api/push/apns-register-widget",
                method: "POST",
                body: Body(token: tokenHex, device_id: deviceId)
            )
            registeredTokenHex = tokenHex
            return true
        } catch {
            return false
        }
    }

    /// DELETE `/api/push/apns-register-widget?device_id=` — best-effort / idempotent.
    ///
    /// Returns `.success` on 2xx/404, `.unauthorized` on 401 (so the caller can
    /// log it — a 401 means the request reached the server without a valid
    /// bearer, leaving an orphan token row; security review critical finding #1),
    /// or `.failure` for other transport/4xx/5xx errors.
    public enum UnregisterOutcome: Equatable {
        case success
        case unauthorized
        case failure
    }

    public static func unregister(deviceId: String) async -> UnregisterOutcome {
        clearCachedToken()
        guard !deviceId.isEmpty else { return .success }

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        let query = components.percentEncodedQuery ?? ""
        let path = "/api/push/apns-register-widget?\(query)"
        do {
            let _: APIResponse<VoidData> = try await APIClient.shared.requestJSON(
                path: path,
                method: "DELETE"
            )
            return .success
        } catch {
            if let apiError = error as? APIError {
                if case .unauthorized = apiError { return .unauthorized }
                if case .httpError(let statusCode) = apiError, statusCode == 401 {
                    return .unauthorized
                }
            }
            return .failure
        }
    }
}
