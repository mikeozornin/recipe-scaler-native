//
//  AuthService.swift
//  RecipeScalerNative
//
//

import Foundation
import KeychainAccess
import RecipeScalerCore

// MARK: - Auth Models
struct AuthTokenPayload: Decodable {
    struct AuthUser: Decodable {
        let id: String
        let dataVersion: String?

        enum CodingKeys: String, CodingKey {
            case id
            case dataVersion = "data_version"
        }
    }

    let user: AuthUser
    let deviceToken: String?
    let seedPhrase: String?

    enum CodingKeys: String, CodingKey {
        case user
        case deviceToken = "device_token"
        case seedPhrase = "seed_phrase"
    }
}

struct LoginRequest: Encodable {
    let seedPhrase: String
    let deviceId: String
    let platform: String
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case seedPhrase = "seed_phrase"
        case deviceId = "device_id"
        case platform
        case appVersion = "app_version"
    }
}

struct RegisterAutoRequest: Encodable {
    let deviceId: String
    let platform: String
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case platform
        case appVersion = "app_version"
    }
}

struct ExchangeSeedForTokenRequest: Encodable {
    let seedPhrase: String
    let deviceId: String
    let platform: String
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case seedPhrase = "seed_phrase"
        case deviceId = "device_id"
        case platform
        case appVersion = "app_version"
    }
}

/// Spec 055: irreversible account deletion. The client sends the seed phrase;
/// the server re-validates BIP39 + sha256 against `users.seed_hash` before
/// deleting the account.
struct DeleteAccountRequest: Encodable {
    let seedPhrase: String

    enum CodingKeys: String, CodingKey {
        case seedPhrase = "seed_phrase"
    }
}

/// Spec 055: the delete-account response carries no `data` payload — just
/// `{ success: true }`. `APIResponse<T>` requires a Decodable `T` for the
/// optional `data` field; this empty type decodes successfully and is always nil.
struct EmptyPayload: Decodable {}

// MARK: - Auth Errors
enum AuthError: LocalizedError {
    case keychainError(String)
    case decodingError(Error)
    case networkError(String)
    case invalidSeedPhrase
    case seedPhraseNotFound
    case apiError(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .keychainError:
            return Bundle.currentLocalizedString("auth.error.keychain")
        case .decodingError:
            return Bundle.currentLocalizedString("auth.error.decoding")
        case .networkError:
            return Bundle.currentLocalizedString("auth.error.network")
        case .invalidSeedPhrase:
            return Bundle.currentLocalizedString("auth.error.invalid-seed")
        case .seedPhraseNotFound:
            return Bundle.currentLocalizedString("auth.error.seed-not-found")
        case .apiError(_, let message):
            return AuthError.localizeServerMessage(message)
        case .invalidResponse:
            return Bundle.currentLocalizedString("auth.error.invalid-response")
        }
    }

    /// Resolve a server-supplied message into a user-facing localized string.
    /// Server contract: `response.error` should be a dot-key (e.g. `auth.register.failed`);
    /// legacy English strings fall back to a generic localized message.
    static func localizeServerMessage(_ message: String) -> String {
        DotKeyLocalizer.localize(message: message, fallbackKey: "auth.error.api-generic")
    }

    /// User-facing message for view-layer consumption (idiomatic alongside `APIError.userFacingMessage()`).
    func userFacingMessage() -> String {
        errorDescription ?? Bundle.currentLocalizedString("auth.error.api-generic")
    }
}

// MARK: - Spec 055 Phase R: account invalidation types

/// What kind of signal triggered the runtime account-invalidation flow.
/// Logged via `AppLog` for diagnostics; never reaches the UI.
enum AccountInvalidationReason: String, Sendable {
    /// Socket.IO `auth_error` with `message == "Account deleted"` — server
    /// confirmed post-commit teardown (spec 055 US5 online peer path).
    case socketSignal
    /// REST 401 → `exchange-seed-for-token` → `404 User not found`. Account
    /// was deleted while this device was offline (spec 055 US5 offline path).
    case restInvalidation
}

/// Why the local session is being wiped. Mirrors the cold-start `staleSession`
/// case from spec 054 plus the runtime recovery paths added in spec 055 Phase R.
/// Logged via `AppLog.info(.app, "session_wiped", data: ["reason": ...])`.
enum SessionWipeReason: String, Sendable {
    case staleSession
    case accountDeletedSocket
    case accountDeletedRest
    case lightRevoke
    case explicitDeleteAccount
}

/// Outcome of `exchange-seed-for-token` when recovering from a 401. Used so
/// tests can stub the network without hitting the server.
enum DeviceTokenExchangeOutcome: Sendable {
    /// Exchange succeeded — apply the new token, keep the session alive.
    case token(String)
    /// `404 User not found` — the account was deleted while this device was
    /// offline. Trigger full wipe.
    case userNotFound
    /// Any other failure (5xx, network error, malformed response). Light
    /// revoke: clear auth state but keep local data so the user can retry.
    case transient
}

// MARK: - Auth Service
@MainActor
@Observable
class AuthService {
    /// Shim: returns `AppContainer.shared.auth` when the container is
    /// constructed, otherwise a stand-alone instance. Stand-alone is created
    /// lazily on first access (e.g. from a DEBUG preview without container).
    static var shared: AuthService {
        if let container = AppContainer.shared {
            return container.auth
        }
        return Standalone
    }

    private static let Standalone = AuthService()

    var isAuthenticated = false
    var userId: String?
    var token: String?

    /// Spec 054: probe used by `performStaleSessionHealthCheck()` to verify the
    /// restored user still exists on the server. Indirected through a closure
    /// so unit tests can inject a stub without hitting the network.
    var checkUserExistsProvider: () async -> UserExistsResult = { await AccountAPI.checkUserExists() }

    /// Spec 055 Phase R: seed-exchange recovery stub for `handleDeviceTokenInvalid()`.
    /// Default implementation calls `exchangeSeedForToken(seedPhrase:)` on this
    /// instance; tests override to inject `.token` / `.userNotFound` / `.transient`
    /// outcomes without hitting the network.
    var exchangeSeedForTokenRecoveryProvider: (String) async -> DeviceTokenExchangeOutcome = { seed in
        do {
            let token = try await AuthService.shared.exchangeSeedForToken(seedPhrase: seed)
            return .token(token)
        } catch AuthError.apiError(let statusCode, let message) {
            // Spec 055 Phase R FR-R2: server returns 404 when the user row is
            // gone (CASCADE deleted alongside `users`). Legacy paths may emit
            // 400/401 with a "user not found" message — match the exact phrase
            // (case-insensitive) rather than the loose "not found" substring
            // so benign errors like "Recipe not found" cannot trigger a wipe.
            let lowercased = message.lowercased()
            let isUserNotFoundPhrase = lowercased == "user not found"
                || lowercased.contains("user not found")
            if statusCode == 404 || isUserNotFoundPhrase {
                return .userNotFound
            }
            return .transient
        } catch {
            return .transient
        }
    }

    /// Spec 038: stub for `markFeatureInstalled()`'s fire-and-forget POST so
    /// unit tests can assert call counts without hitting the network. Default
    /// implementation delegates to `AccountAPI.markFeatureAdoption(_:)`.
    var markFeatureAdoptionProvider: (FeatureAdoptionClientFeature) async throws -> Void = { feature in
        try await AccountAPI.markFeatureAdoption(feature)
    }

    /// Spec 055 Phase R: re-entry guard. Multiple sources (socket `auth_error`,
    /// REST 401, race-induced double-fire) can call `handleAccountDeleted` in
    /// burst. Without this guard, teardown runs N times — the second pass
    /// no-ops on an empty Keychain but still churns the UI and emits duplicate
    /// `account_deleted` audits.
    private var isHandlingAccountInvalidation = false

    private let keychain = Keychain(service: "com.recipescaler.native")
    private let seedPhraseKey = "seedPhrase"

    private var apiClient: APIClient {
        APIClient.shared
    }

    init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isUITesting = ProcessInfo.processInfo.arguments.contains("ui-testing")

        if isTesting || isUITesting {
            isAuthenticated = false
            userId = nil
            token = nil
            return
        }

        // One-shot purge of plaintext credentials from older app versions that
        // stored userId / authToken in UserDefaults (both the standard suite and
        // the App Group mirror). The current session is now backed by the Keychain
        // (SharedAuthStore), so any leftover plaintext copy is removed unconditionally.
        // Idempotent and cheap; runs once per cold start.
        purgeLegacyUserDefaultsCredentials()

        // Restore authentication state from Keychain
        restoreAuthenticationState()
    }

    // MARK: - Private Methods
    private func restoreAuthenticationState() {
        guard let restoredUserId = SharedAuthStore.userId else { return }

        let restoredToken = SharedAuthStore.token
        applySession(userId: restoredUserId, deviceToken: restoredToken)

        if restoredToken == nil {
            Task { await ensureDeviceTokenMigratedIfNeeded() }
        }
        // Spec 054: stale-session health-check is awaited from
        // `AppContainer.bootstrap(userId:)` BEFORE `sync.start`, so a stale
        // user is wiped before any socket/timer tries to authenticate with it.
    }

    /// Spec 054: cold-start probe. Idempotent; safe to call from
    /// `AppContainer.bootstrap(userId:)`.
    ///
    /// On `.userMissing` or `.unauthorized` the local session is fully wiped
    /// (Keychain seed, SharedAuthStore, APIClient, watch) and the UI falls
    /// back to `AuthView` because `isAuthenticated == false`. Transient
    /// failures (network / 5xx) leave the session intact so a temporary
    /// outage doesn't log the user out.
    ///
    /// Gating (XCTest, simulator DEBUG auto-login) is the caller's
    /// responsibility — `AppContainer.bootstrap` already short-circuits
    /// under `XCTestConfigurationFilePath` / `ui-testing`. This method itself
    /// is pure logic so it can be unit-tested with a stub probe.
    func performStaleSessionHealthCheck() async {
        guard SharedAuthStore.userId != nil, isAuthenticated else { return }

        let result = await checkUserExistsProvider()
        switch result {
        case .exists, .transient:
            AppLog.info(.app, "stale_session_check_ok", data: ["result": "\(result)"])
        case .userMissing, .unauthorized:
            AppLog.info(.app, "stale_session_detected", data: ["result": "\(result)"])
            wipeLocalSession(reason: .staleSession)
            AppLog.info(.app, "stale_session_cleared", data: ["result": "\(result)"])
        }
    }

    // MARK: - Spec 055 Phase R: runtime account-invalidation recovery

    /// Centralized entry point for "server says the account is gone".
    ///
    /// Idempotent: a re-entry guard ensures the wipe + teardown runs at most
    /// once even when multiple signals (`auth_error` + REST 401) fire in
    /// burst. After wipe, `isAuthenticated == false` flips and
    /// `ContentView.onChange(of: authService.isAuthenticated)` runs the
    /// sync/container teardown (`clearSessionForLogout` + `stopForLogout`).
    ///
    /// UX: silent. No banners, no alerts — the user just lands on `AuthView`.
    /// Web parity: `handleAccountDeletedLocal()` in
    /// `recipe-scaler-web/recipe-scaler/src/services/auth-session-revoked.ts`.
    func handleAccountDeleted(reason: AccountInvalidationReason) async {
        guard !isHandlingAccountInvalidation else { return }
        isHandlingAccountInvalidation = true
        defer { isHandlingAccountInvalidation = false }

        let wipeReason: SessionWipeReason = reason == .socketSignal
            ? .accountDeletedSocket
            : .accountDeletedRest

        AppLog.info(.app, "account_invalidation", data: [
            "source": reason.rawValue,
            "wipe_reason": wipeReason.rawValue,
        ])

        await performInvalidationTeardown(wipeReason: wipeReason)
    }

    /// Shared wipe + container teardown. Called from `handleAccountDeleted`
    /// and from the `userNotFound` branch of `handleDeviceTokenInvalid`.
    /// Assumes the re-entry guard is already held by the caller — does not
    /// re-check it (so internal delegation from REST → wipe is not blocked
    /// by the guard set at the top of `handleDeviceTokenInvalid`).
    private func performInvalidationTeardown(wipeReason: SessionWipeReason) async {
        wipeLocalSession(reason: wipeReason)

        // `ContentView.onChange(isAuthenticated)` will fire from the flip
        // above and run `clearSessionForLogout` + `stopForLogout`. We call
        // them defensively here too so the state is consistent even if the
        // SwiftUI environment hasn't observed the change yet (e.g. tests,
        // extensions, app not in foreground).
        if let container = AppContainer.shared {
            await container.sync.clearSessionForLogout()
            await container.stopForLogout()
        }
    }

    /// REST 401 recovery (spec 055 US5 offline path).
    ///
    /// Called by `APIClient.unauthorizedHandler` when any authenticated REST
    /// call returns 401. The device token may be revoked for several reasons
    /// (account deletion, admin revoke, rotation) — only treat the account as
    /// deleted when the server confirms via `exchange-seed-for-token` →
    /// `404 User not found`. On success the session is silently recovered;
    /// on transient failure we light-revoke (clear auth, keep local data).
    ///
    /// Web parity: `handleAuthFailureResponse()` in
    /// `recipe-scaler-web/recipe-scaler/src/services/auth-session-revoked.ts`.
    ///
    /// Re-entry guard spans the entire method (including the awaited seed
    /// exchange) so a burst of REST 401s collapses into a single recovery
    /// attempt — FR-R5 invariant.
    func handleDeviceTokenInvalid() async {
        guard !isHandlingAccountInvalidation else { return }
        isHandlingAccountInvalidation = true
        defer { isHandlingAccountInvalidation = false }

        let seed: String
        do {
            seed = try retrieveSeedPhraseFromKeychain()
        } catch {
            // No seed to recover with — wipe silently. Local data stays
            // (logout() path wipes seed; recovery without it is impossible).
            AppLog.info(.app, "device_token_recovery_no_seed")
            wipeLocalSession(reason: .lightRevoke)
            return
        }

        let outcome = await exchangeSeedForTokenRecoveryProvider(seed)

        switch outcome {
        case .token(let newToken):
            guard let userId = SharedAuthStore.userId ?? userId else {
                AppLog.info(.app, "device_token_recovery_no_user")
                wipeLocalSession(reason: .lightRevoke)
                return
            }
            applySession(userId: userId, deviceToken: newToken)
            AppLog.info(.app, "device_token_recovered")

        case .userNotFound:
            AppLog.info(.app, "device_token_recovery_user_not_found")
            // Full wipe — account is gone. Inline into the teardown helper
            // instead of delegating to `handleAccountDeleted` (which would
            // short-circuit via the re-entry guard already set above).
            await performInvalidationTeardown(wipeReason: .accountDeletedRest)

        case .transient:
            AppLog.info(.app, "device_token_recovery_transient")
            // Light revoke — keep local data so the user can retry once the
            // transient condition clears. Web parity: "light-revoke" branch.
            wipeLocalSession(reason: .lightRevoke)
        }
    }

    /// Spec 054 / Spec 055 Phase R: wipe local credentials when the server confirms
    /// the user is gone, or when runtime recovery decides the account was deleted.
    /// Mirrors `logout()` minus the server-side `POST /api/auth/logout` (the user
    /// already doesn't exist) — and never throws, so the wipe is best-effort
    /// even if Keychain access fails mid-way.
    ///
    /// Spec 055 Phase R additions: also clear `RecipeSnapshotStore` so App
    /// Intents cannot resolve recipe entities for a user that no longer
    /// exists, and invalidate any running timer Live Activities (otherwise
    /// they keep showing the deleted user's recipe name on the Lock Screen).
    /// Live Activity teardown is `@MainActor`-isolated and idempotent — safe
    /// to call from every wipe path, including cold-start `staleSession`
    /// where `ContentView.onChange` has not yet wired up `stopForLogout`.
    ///
    /// Note: `ShoppingListSnapshotStore` is intentionally NOT cleared here —
    /// it is not registered in the main app target (only in the Share
    /// extension group). Tracked as a parity gap in the Phase R review
    /// (review-code-reviewer-glm52-max-master.md, finding M6).
    private func wipeLocalSession(reason: SessionWipeReason) {
        AppLog.info(.app, "session_wiped", data: ["reason": reason.rawValue])

        try? deleteSeedPhraseFromKeychain()
        SharedAuthStore.clear()
        WatchCredentialsBridge.shared.purge()
        RecipeSnapshotStore.clear()

        userId = nil
        token = nil
        isAuthenticated = false

        apiClient.configure(authToken: nil)
        apiClient.configure(userId: nil)

        AppContainer.shared?.featureAdoption.clearForLogout()

        // End Live Activities directly so every wipe path (cold-start
        // `staleSession`, runtime `handleAccountDeleted`, light revoke)
        // clears the Lock Screen — not just the explicit-logout path that
        // routes through `AppContainer.stopForLogout`.
        Task { @MainActor in
            await AppContainer.shared?.timerLiveActivityCoordinator.endAll()
        }
    }

    /// Spec 041: silent `/exchange-seed-for-token` when there is a `userId` but no
    /// `SharedAuthStore.token` and the seed phrase is in app-local Keychain.
    ///
    /// Called from cold-start restore and from `AppContainer.bootstrap` so DEBUG
    /// simulator auto-login (hardcoded `debugUserId` without `loginWithSeed`) still
    /// migrates to Bearer before sync/socket start when a seed is available.
    func ensureDeviceTokenMigratedIfNeeded() async {
        await migrateDeviceTokenIfNeeded()
    }

    #if DEBUG
    /// Injects a full Bearer session for DEBUG simulator auto-login (parity with
    /// `E2E_OVERRIDE_USER_ID` + `E2E_OVERRIDE_DEVICE_TOKEN`). Also parks the
    /// documented debug seed in Keychain so Account → Secret Phrase and silent
    /// re-exchange keep working after a wipe.
    func applyDebugSimulatorSession(userId: String, deviceToken: String, seedPhrase: String) {
        applySession(userId: userId, deviceToken: deviceToken)
        try? saveSeedPhraseToKeychain(seedPhrase)
    }
    #endif

    private func applySession(userId: String, deviceToken: String?) {
        SharedAuthStore.userId = userId
        if let deviceToken, !deviceToken.isEmpty {
            SharedAuthStore.token = deviceToken
        }

        self.userId = userId
        self.token = deviceToken
        self.isAuthenticated = true

        configureAPIClient(userId: userId, deviceToken: deviceToken)
        WatchCredentialsBridge.shared.publish(
            userId: userId,
            token: SharedAuthStore.token
        )
    }

    private func configureAPIClient(userId: String, deviceToken: String?) {
        if let deviceToken, !deviceToken.isEmpty {
            apiClient.configure(authToken: deviceToken)
            apiClient.configure(userId: userId)
        } else {
            apiClient.configure(authToken: nil)
            apiClient.configure(userId: userId)
        }
    }

    /// Silent migration for sessions restored from Keychain without a device token (spec 041).
    ///
    /// Deliberately does NOT delete the seed phrase from Keychain after a successful
    /// exchange. The seed is the user's recovery/root credential and must stay
    /// available so they can view it in Account → Secret Phrase and sign in on
    /// another device. The seed is wiped only by `logout()`.
    private func migrateDeviceTokenIfNeeded() async {
        guard SharedAuthStore.token == nil else { return }
        guard SharedAuthStore.userId != nil else { return }

        let seed: String
        do {
            seed = try retrieveSeedPhraseFromKeychain()
        } catch {
            return
        }

        do {
            let token = try await exchangeSeedForToken(seedPhrase: seed)
            guard let userId = SharedAuthStore.userId else { return }
            applySession(userId: userId, deviceToken: token)
            AppLog.info(.app, "device_token_migrated_on_launch")
        } catch {
            AppLog.info(.app, "device_token_migration_skipped", data: [
                "reason": String(describing: type(of: error)),
            ])
        }
    }

    func exchangeSeedForToken(seedPhrase: String) async throws -> String {
        let body = ExchangeSeedForTokenRequest(
            seedPhrase: seedPhrase,
            deviceId: TimerSyncService.storedDeviceId(),
            platform: AuthClientMetadata.nativePlatform,
            appVersion: AuthClientMetadata.appVersion()
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(body)

        let response: APIResponse<AuthTokenPayload> = try await performAuthRequest(
            path: "/api/auth/exchange-seed-for-token",
            method: "POST",
            body: data
        )

        guard response.success,
              let payload = response.data,
              let token = payload.deviceToken,
              !token.isEmpty
        else {
            throw AuthError.apiError(
                statusCode: 400,
                message: response.error ?? "auth.error.api-generic"
            )
        }

        return token
    }

    /// Wipe plaintext credentials that older versions wrote to UserDefaults.
    /// After this call the only durable copy of `userId` lives in the Keychain
    /// via `SharedAuthStore`. Safe to invoke when nothing is stored yet.
    private func purgeLegacyUserDefaultsCredentials() {
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults(suiteName: AppGroup.id)?
            .removeObject(forKey: SharedAuthStore.legacyAppGroupUserIdKey)
    }

    private func saveSeedPhraseToKeychain(_ seedPhrase: String) throws {
        do {
            try keychain.set(seedPhrase, key: seedPhraseKey)
        } catch {
            throw AuthError.keychainError("save_seed_phrase")
        }
    }

    private func retrieveSeedPhraseFromKeychain() throws -> String {
        do {
            guard let seedPhrase = try keychain.get(seedPhraseKey) else {
                throw AuthError.seedPhraseNotFound
            }
            return seedPhrase
        } catch {
            if error is AuthError {
                throw error
            }
            throw AuthError.keychainError("retrieve_seed_phrase")
        }
    }

    private func deleteSeedPhraseFromKeychain() throws {
        do {
            try keychain.remove(seedPhraseKey)
        } catch {
            throw AuthError.keychainError("delete_seed_phrase")
        }
    }

    private func buildAuthRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: "\(Config.baseURL)\(path)") else {
            throw AuthError.networkError("invalid_url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body
        return request
    }

    private func performAuthRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        let request = try buildAuthRequest(path: path, method: method, body: body)

        let (data, response) = try await AppURLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            apiClient.notifyUnauthorizedIfNeeded(statusCode: httpResponse.statusCode)
            if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorResponse["error"] ?? errorResponse["message"] {
                throw AuthError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            throw AuthError.apiError(statusCode: httpResponse.statusCode, message: "auth.error.api-generic")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AuthError.decodingError(error)
        }
    }

    // MARK: - Public Methods

    /// Register a new user with automatic seed phrase generation
    /// - Returns: A tuple containing userId, seedPhrase, and authToken
    func registerAuto() async throws -> (userId: String, seedPhrase: String, token: String) {
        let body = RegisterAutoRequest(
            deviceId: TimerSyncService.storedDeviceId(),
            platform: AuthClientMetadata.nativePlatform,
            appVersion: AuthClientMetadata.appVersion()
        )
        let encoded = try JSONEncoder().encode(body)

        let response: APIResponse<AuthTokenPayload> = try await performAuthRequest(
            path: "/api/auth/register-auto",
            method: "POST",
            body: encoded
        )

        guard response.success, let data = response.data else {
            throw AuthError.apiError(
                statusCode: 400,
                message: response.error ?? "auth.register.failed"
            )
        }

        guard let seedPhrase = data.seedPhrase else {
            throw AuthError.invalidResponse
        }

        try saveSeedPhraseToKeychain(seedPhrase)

        let deviceToken = data.deviceToken ?? ""
        applySession(userId: data.user.id, deviceToken: deviceToken.isEmpty ? nil : deviceToken)

        if let featureAdoption = AppContainer.shared?.featureAdoption {
            markFeatureInstalled(featureAdoptionStore: featureAdoption)
        }

        return (userId: data.user.id, seedPhrase: seedPhrase, token: deviceToken)
    }

    /// Login with a seed phrase
    /// - Parameter seedPhrase: The 12-word seed phrase (words separated by spaces)
    /// - Returns: A tuple containing userId and authToken
    func loginWithSeed(_ seedPhrase: String) async throws -> (userId: String, token: String) {
        // Validate seed phrase format (12 words)
        let words = seedPhrase.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard words.count == 12 else {
            throw AuthError.invalidSeedPhrase
        }

        let loginRequest = LoginRequest(
            seedPhrase: seedPhrase,
            deviceId: TimerSyncService.storedDeviceId(),
            platform: AuthClientMetadata.nativePlatform,
            appVersion: AuthClientMetadata.appVersion()
        )
        let body = try JSONEncoder().encode(loginRequest)

        let response: APIResponse<AuthTokenPayload> = try await performAuthRequest(
            path: "/api/auth/login-with-seed",
            method: "POST",
            body: body
        )

        guard response.success, let data = response.data else {
            throw AuthError.apiError(
                statusCode: 400,
                message: response.error ?? "auth.login.failed"
            )
        }

        try saveSeedPhraseToKeychain(seedPhrase)

        let deviceToken = data.deviceToken ?? ""
        applySession(userId: data.user.id, deviceToken: deviceToken.isEmpty ? nil : deviceToken)

        if let featureAdoption = AppContainer.shared?.featureAdoption {
            markFeatureInstalled(featureAdoptionStore: featureAdoption)
        }

        return (userId: data.user.id, token: deviceToken)
    }

    /// Logout the current user
    func logout() throws {
        // The seed phrase is the recovery credential; wipe it ONLY on explicit
        // logout. Migration (`migrateDeviceTokenIfNeeded`) deliberately keeps it
        // so the user can still view it in Account → Secret Phrase and sign in
        // on another device.
        try deleteSeedPhraseFromKeychain()

        // Remove the shared userId from the Keychain so extensions can no
        // longer authenticate on behalf of this user.
        SharedAuthStore.clear()

        // Spec 039: tell the paired Apple Watch to purge its local creds.
        WatchCredentialsBridge.shared.purge()

        // Reset published properties
        self.userId = nil
        self.token = nil
        self.isAuthenticated = false

        apiClient.configure(authToken: nil)
        apiClient.configure(userId: nil)

        AppContainer.shared?.featureAdoption.clearForLogout()
    }

    /// Spec 055: irreversibly delete the current account.
    ///
    /// Re-validates the seed phrase client-side (12 words) for immediate
    /// feedback, then POSTs `/api/auth/delete-account`. The server re-checks
    /// BIP39 + sha256(seed) against `users.seed_hash`; a mismatch surfaces as
    /// an `AuthError.apiError(401, ...)`.
    ///
    /// On success credentials are wiped via `wipeLocalSession()` (best-effort,
    /// never throws — the server already deleted the account). The caller then
    /// runs Yjs / container teardown (`clearSessionForLogout` + `stopForLogout`).
    /// Do **not** wipe local stores before this call: a failed POST must leave
    /// the session intact (web parity).
    func deleteAccount(seedPhrase: String) async throws {
        let words = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
        guard words.count == 12 else {
            throw AuthError.invalidSeedPhrase
        }

        let body = DeleteAccountRequest(seedPhrase: seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines))
        let data = try JSONEncoder().encode(body)

        let response: APIResponse<EmptyPayload> = try await performAuthRequest(
            path: "/api/auth/delete-account",
            method: "POST",
            body: data
        )

        guard response.success else {
            throw AuthError.apiError(
                statusCode: 400,
                message: response.error ?? "account.delete.failed"
            )
        }

        // Account is already gone server-side — never throw from local purge.
        wipeLocalSession(reason: .explicitDeleteAccount)
    }

    /// Get the current authentication status
    var isAuthenticatedBool: Bool {
        return isAuthenticated
    }

    /// Retrieve the stored seed phrase from Keychain
    func getSeedPhrase() throws -> String {
        return try retrieveSeedPhraseFromKeychain()
    }

    // MARK: - Feature adoption (spec 038)

    /// Records `installed_native_app` on first successful native-app auth on this
    /// account. Idempotent via the `feature-adoption.installed-reported` UserDefaults
    /// flag: once the POST succeeds, the flag is set and subsequent launches on the
    /// same account skip the call entirely. On failure the flag stays unset and the
    /// next cold start retries.
    ///
    /// Called only from `registerAuto()` and `loginWithSeed(_:)` (first native login).
    /// Deliberately NOT called from `restoreAuthenticationState()` — that is a same-device
    /// session restore, not a new native-app sign-in.
    ///
    /// The `installed-reported` flag is wiped by `FeatureAdoptionStore.clearForLogout()`
    /// (logout / account-deletion / wipe paths) so a previous account's flag does not
    /// block the POST when a different account signs in on the same device — spec 038
    /// changelog 2026-08-03.
    ///
    /// Session-identity guard: the POST is fire-and-forget. If the user logs out
    /// while it is in flight, `clearForLogout()` wipes `installed-reported`. The
    /// success branch captures the `userId` *before* the POST and re-checks it
    /// against the current `SharedAuthStore.userId` before writing the flag — so
    /// a completed POST for user A can no longer re-arm the device flag right
    /// after user B signed in. Without this guard the original multi-account
    /// bug would resurface through a realistic ~100ms–2s logout race (spec 038
    /// changelog 2026-08-03, code review finding HIGH-1).
    func markFeatureInstalled(featureAdoptionStore: FeatureAdoptionStore) {
        let reportedKey = FeatureAdoptionStore.installedReportedKey
        guard !UserDefaults.standard.bool(forKey: reportedKey) else {
            AppLog.info(.app, "feature_adoption_installed_skip", data: [
                "reason": "already_reported"
            ])
            return
        }

        let sessionUserId = SharedAuthStore.userId
        AppLog.info(.app, "feature_adoption_installed_begin")
        featureAdoptionStore.markInstalledLocally()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.markFeatureAdoptionProvider(.installedNativeApp)
                // Re-check session identity before persisting the idempotency
                // flag: a logout/account-switch that completed during the POST
                // round-trip would otherwise let this write re-arm the device
                // flag for the next account.
                guard SharedAuthStore.userId == sessionUserId, sessionUserId != nil else {
                    AppLog.info(.app, "feature_adoption_installed_skip_persist", data: [
                        "reason": "session_changed_in_flight"
                    ])
                    return
                }
                UserDefaults.standard.set(true, forKey: reportedKey)
                AppLog.info(.app, "feature_adoption_installed_ok")
            } catch {
                // Leave the flag unset; retry on next launch / login.
                AppLog.info(.app, "feature_adoption_installed_failed", data: [
                    "reason": String(describing: type(of: error))
                ])
            }
        }
    }
}
