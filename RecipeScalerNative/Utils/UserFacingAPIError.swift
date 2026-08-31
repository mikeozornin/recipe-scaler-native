//
//  UserFacingAPIError.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

enum UserFacingAPIError {
    /// User-facing message for any `Error`. Order:
    /// 1. Cancellation → empty (callers should skip UI).
    /// 2. `APIError` / `AuthError` / `YrsError` → their typed `userFacingMessage()`.
    /// 3. Transient URLError → short localized "no connection".
    /// 4. Fallback → generic localized "Something went wrong".
    static func message(for error: Error) -> String {
        if error is CancellationError {
            return ""
        }
        if let apiError = error as? APIError {
            return apiError.userFacingMessage()
        }
        if let authError = error as? AuthError {
            return authError.userFacingMessage()
        }
        if let yrsError = error as? YrsError {
            return yrsError.userFacingMessage()
        }
        if let editError = error as? RecipeEditError {
            return editError.localizedDescription
        }
        if isTransientNetworkError(error) {
            return Bundle.currentLocalizedString("account.error.unreachable")
        }
        return Bundle.currentLocalizedString("account.error.generic")
    }

    /// URLSession / transport failures that should not surface raw `localizedDescription` in UI.
    static func isTransientNetworkError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError {
            return isTransientNetworkURLError(urlError.code)
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return isTransientNetworkURLError(URLError.Code(rawValue: nsError.code))
    }

    /// Account profile status strip under settings. Returns `nil` when nothing should be shown.
    static func accountStatusMessage(for error: Error, isBackgroundRefresh: Bool) -> String? {
        if isTransientNetworkError(error) {
            return isBackgroundRefresh ? nil : Bundle.currentLocalizedString("account.error.unreachable")
        }
        if let apiError = error as? APIError {
            return apiError.userFacingMessage()
        }
        if let authError = error as? AuthError {
            return authError.userFacingMessage()
        }
        if let yrsError = error as? YrsError {
            return yrsError.userFacingMessage()
        }
        return Bundle.currentLocalizedString("account.error.generic")
    }

    private static func isTransientNetworkURLError(_ code: URLError.Code) -> Bool {
        switch code {
        case .cancelled:
            return true
        case .timedOut,
             .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}