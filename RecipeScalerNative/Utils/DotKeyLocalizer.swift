//
//  DotKeyLocalizer.swift
//  RecipeScalerNative
//
//  Safe-decoder helper for server-supplied dot-key messages
//  (e.g. `assistant.threads.create.failed`) — resolves them via the
//  runtime-language bundle, with a fallback key for legacy English.
//
//  Scope (after spec 031 v2 — typed `ServerErrorCode`):
//  - Most throw-sites now build `APIError.serverError(code: ServerErrorCode)` directly.
//    `ServerErrorCode.from(serverValue:fallback:)` collapses unknown / legacy strings
//    into a known fallback, and `userFacingMessage()` resolves via `code.rawValue`.
//    No prefix-sniffing at the view layer for these paths.
//  - `DotKeyLocalizer` is retained for the few code paths that still pass a raw
//    `String` from the server (notably `AuthError.apiError(_, message:)` in
//    `AuthService.swift`) until those are migrated to `ServerErrorCode` too.
//  - Tests in `ErrorLocalizationTests` cover the regex itself.
//
//  Contract: specs/031-error-i18n/server-error-keys.md
//

import Foundation

enum DotKeyLocalizer {
    /// Regular expression matching a dot-key message:
    ///   lowercase ASCII + digits + hyphen, at least two dot-separated segments.
    ///   Examples: `assistant.threads.create.failed`, `account.profile.load-failed`.
    ///   Counter-examples rejected: `Profile load failed`, `assistant error`, `Failed: 42`.
    private static let dotKeyPattern = #"^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*){1,}$"#

    /// True when `message` matches the dot-key contract.
    static func looksLikeDotKey(_ message: String) -> Bool {
        message.range(of: dotKeyPattern, options: .regularExpression) != nil
    }

    /// Resolve a server-supplied message into a user-facing localized string.
    /// - If `message` is a dot-key, it is resolved through `Bundle.currentLocalizedString`.
    /// - Otherwise `fallbackKey` is resolved (typically a generic localized message).
    /// - Parameter allowSuffix: when true, anything after `:` in a dot-key is stripped
    ///   (used by `ImportPhotoValidator`-style `key:arg1:arg2` payloads).
    static func localize(message: String, fallbackKey: String, allowSuffix: Bool = false) -> String {
        guard looksLikeDotKey(message) else {
            return Bundle.currentLocalizedString(fallbackKey)
        }
        let key = allowSuffix
            ? (message.split(separator: ":", maxSplits: 1).first.map(String.init) ?? message)
            : message
        return Bundle.currentLocalizedString(key)
    }
}
