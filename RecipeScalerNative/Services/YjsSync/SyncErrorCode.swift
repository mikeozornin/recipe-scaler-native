//
//  SyncErrorCode.swift
//  RecipeScalerNative
//
//  Typed catalog of Socket.IO `sync_error` codes.
//
//  Replaces the previous substring-sniffing flow in `YjsSyncService.handleSyncError`
//  / `localizedSyncError`, which matched raw English server strings with
//  `message.contains(...)` and could leak English into the UI via the final
//  `return message` fallback.
//
//  Mirrors the typed `ServerErrorCode` pattern (spec 031) but covers the
//  Socket.IO `sync_error` event instead of the REST `APIResponse.error` field.
//
//  Contract: specs/031-error-i18n/sync-error-codes.md
//

import Foundation

/// Typed catalog of all dot-keys the server may return in the `sync_error`
/// Socket.IO event's `code` field.
///
/// Decoding strategy (`from(code:legacyMessage:fallback:)`):
/// 1. If the payload carries a future `code` dot-key, resolve it directly.
/// 2. Otherwise fall back to matching the legacy English `error` substring
///    (preserves behavior with un-migrated servers).
/// 3. Otherwise return `fallback` (defaults to `.generic`), guaranteeing the
///    caller never sees a raw `String` of unknown shape.
///
/// The view layer resolves via `Bundle.currentLocalizedString(code.rawValue)`
/// through the `localizedMessage` extension — no prefix-sniffing on the view side.
public enum SyncErrorCode: String, Sendable, Equatable, CaseIterable {
    case ownershipFailed      = "sync.error.ownership"
    case recipeDeleted        = "sync.error.recipe-deleted"
    case emptyUpdate          = "sync.error.empty-update"
    case invalidUpdate        = "sync.error.invalid-update"
    case truncatedCollection  = "sync.error.truncated-collection"
    case generic              = "sync.error.generic"

    /// Resolve a `sync_error` payload into a typed code.
    ///
    /// - Parameters:
    ///   - code: Future dot-key from `payload["code"]`. Takes precedence over
    ///     the legacy message when present and recognized. Accepts both the
    ///     client dot-key (`sync.error.truncated-collection`) and the server
    ///     wire code (`truncated_collection`).
    ///   - legacyMessage: Today's English `payload["error"]` string. Used only
    ///     when `code` is missing or unknown — preserves client behavior with
    ///     un-migrated servers.
    ///   - fallback: Code returned when neither `code` nor `legacyMessage`
    ///     matches a known pattern.
    public static func from(
        code: String?,
        legacyMessage: String?,
        fallback: SyncErrorCode = .generic
    ) -> SyncErrorCode {
        if let code, !code.isEmpty {
            if let resolved = SyncErrorCode(rawValue: code) {
                return resolved
            }
            if code == "truncated_collection" { return .truncatedCollection }
        }
        if let legacyMessage, !legacyMessage.isEmpty {
            if legacyMessage.contains("Ownership validation failed") { return .ownershipFailed }
            if legacyMessage.contains("Recipe is deleted")          { return .recipeDeleted }
            if legacyMessage.contains("Invalid update")             { return .invalidUpdate }
            if legacyMessage.contains("Empty update")             { return .emptyUpdate }
            if legacyMessage.contains("truncated collection")
                || legacyMessage.contains("truncated_collection") { return .truncatedCollection }
        }
        return fallback
    }

    /// User-facing localized message, resolved through the runtime bundle.
    ///
    /// Equivalent to the previous `localizedSyncError(_:)` flow but without the
    /// `return message` fallback that leaked English into the UI.
    var localizedMessage: String {
        Bundle.currentLocalizedString(rawValue)
    }
}
