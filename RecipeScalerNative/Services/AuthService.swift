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
    /// device. Idempotent via the `feature-adoption.installed-reported` UserDefaults
    /// flag: once the POST succeeds, the flag is set and subsequent logins skip the
    /// call entirely. On failure the flag stays unset and the next cold start retries.
    ///
    /// Called only from `registerAuto()` and `loginWithSeed(_:)` (first native login).
    /// Deliberately NOT called from `restoreAuthenticationState()` — that is a same-device
    /// session restore, not a new native-app sign-in.
    func markFeatureInstalled(featureAdoptionStore: FeatureAdoptionStore) {
        let reportedKey = "feature-adoption.installed-reported"
        guard !UserDefaults.standard.bool(forKey: reportedKey) else { return }

        featureAdoptionStore.markInstalledLocally()

        Task { @MainActor [weak self] in
            guard self != nil else { return }
            do {
                try await AccountAPI.markFeatureAdoption(.installedNativeApp)
                UserDefaults.standard.set(true, forKey: reportedKey)
            } catch {
                // Leave the flag unset; retry on next launch / login.
            }
        }
    }
}
