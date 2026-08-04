//
//  APIError+Localization.swift
//  RecipeScalerNative
//
//  Resolves `APIError` (defined in RecipeScalerCore) into user-facing localized
//  strings via `Bundle.currentLocalizedString`. The Core enum only emits dot-key
//  identifiers from `errorDescription` — this extension performs the final
//  resolution for the Native target and view layer.
//
//  Contract: specs/031-error-i18n/server-error-keys.md
//

import Foundation
import RecipeScalerCore

extension APIError {
    /// User-facing localized message for view-layer consumption.
    ///
    /// - `invalidURL` / `invalidResponse` / `decodingError` / `unauthorized`: fixed localized keys.
    /// - `httpError(code)`: categorical fallback (4xx vs 5xx) — never leaks the raw status code.
    /// - `serverError(code)`: the typed code's `rawValue` is a known dot-key, resolved
    ///   directly via `Bundle.currentLocalizedString`.
    func userFacingMessage() -> String {
        switch self {
        case .invalidURL:
            return Bundle.currentLocalizedString("api.error.invalid-url")
        case .invalidResponse:
            return Bundle.currentLocalizedString("api.error.invalid-response")
        case .decodingError:
            return Bundle.currentLocalizedString("api.error.decoding")
        case .unauthorized:
            return Bundle.currentLocalizedString("api.error.unauthorized")
        case .httpError(let code) where (400...499).contains(code):
            return Bundle.currentLocalizedString("api.error.http-4xx")
        case .httpError(let code) where (500...599).contains(code):
            return Bundle.currentLocalizedString("api.error.http-5xx")
        case .httpError:
            return Bundle.currentLocalizedString("api.error.server-generic")
        case .serverError(let code):
            return Bundle.currentLocalizedString(code.rawValue)
        case .upstreamMessage(let message):
            // Phrase-map known scrape / captcha failures; otherwise generic import failed.
            return ImportErrorLocalizer.localize(message, bundle: .main)
        }
    }
}

extension RecipeLLMParseAPI.LLMParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyDescription:
            return Bundle.currentLocalizedString("llm.parse-empty")
        case .server(let message):
            return message.isEmpty
                ? Bundle.currentLocalizedString("llm.parse-error")
                : message
        }
    }
}
