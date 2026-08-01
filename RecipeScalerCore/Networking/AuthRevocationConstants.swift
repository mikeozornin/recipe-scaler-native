//
//  AuthRevocationConstants.swift
//  RecipeScalerCore
//
//  Spec 055 Phase R: shared constants for server-side auth session invalidation.
//  Parity with `recipe-scaler-web/recipe-scaler/src/types/auth-api.ts`:
//    - `AUTH_ACCOUNT_DELETED_SOCKET_MESSAGE` = "Account deleted"
//    - `AUTH_ACCOUNT_DELETED_HTTP_CODE` (REST 401 body code) — not yet emitted
//      by the server (web spec 055 US5/US6 covers the socket path); reserved
//      here so the client interceptor can opt-in without a follow-up change.
//    - `device_token_invalid` — REST 401 body code emitted by
//      `requireBearerDeviceToken` middleware when the Bearer is rejected
//      (e.g. after CASCADE deletion of the `devices` row).
//

import Foundation

/// Constants exchanged between server and client when an authenticated
/// session is revoked or the underlying account is deleted.
///
/// Kept in `RecipeScalerCore` so both the main app and extensions share the
/// same string values without duplicating magic strings in handlers.
public enum AuthRevocationConstants {
    /// Socket.IO `auth_error` payload `message` value emitted by
    /// `realtime.disconnectUser` after a successful `DELETE FROM users`
    /// (spec 055 post-commit teardown).
    ///
    /// Source of truth: `recipe-scaler-web/server/src/services/realtime.ts`
    /// (`disconnectUser(room, 'Account deleted')`).
    public static let accountDeletedSocketMessage = "Account deleted"

    /// REST 401 body `code` value emitted by the auth middleware when the
    /// Bearer device token is rejected (revoked, rotated, or the underlying
    /// `devices` row was CASCADE-deleted with the user).
    ///
    /// Source of truth: `recipe-scaler-web/server/src/middleware/auth.ts`
    /// (`requireBearerDeviceToken`).
    public static let deviceTokenInvalidCode = "device_token_invalid"

    /// Reserved for future server-side emission of an explicit
    /// "account deleted" REST 401 body code (web parity with
    /// `AUTH_ACCOUNT_DELETED_HTTP_CODE`). The server currently relies on the
    /// socket `auth_error` path for online peers and on
    /// `device_token_invalid` + exchange `404 User not found` for offline
    /// peers — this constant exists so the client can match it without a
    /// follow-up client release if the server starts emitting it.
    public static let accountDeletedRestCode = "account_deleted"
}
