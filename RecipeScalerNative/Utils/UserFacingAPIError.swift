//
//  UserFacingAPIError.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

enum UserFacingAPIError {
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
            return isBackgroundRefresh ? nil : String(localized: "account.error.unreachable")
        }
        if case APIError.serverError(let message) = error, !message.isEmpty {
            return message
        }
        return String(localized: "account.error.generic")
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