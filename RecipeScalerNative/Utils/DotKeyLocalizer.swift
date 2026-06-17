//
//  DotKeyLocalizer.swift
//  RecipeScalerNative
//
//  Shared helper for detecting server-supplied dot-key messages
//  (e.g. `assistant.threads.create.failed`) and resolving them via the
//  runtime-language bundle. Used by APIError and AuthError localization.
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
