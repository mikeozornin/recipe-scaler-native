//
//  AuthService.swift
//  RecipeScalerNative
//
//

import Foundation
import KeychainAccess

// MARK: - Auth Models
struct AuthResponse: Decodable {
    struct AuthUser: Decodable {
        let id: String
    }

    let user: AuthUser
}

struct RegisterAutoResponse: Decodable {
    struct AuthUser: Decodable {
        let id: String
    }

    let user: AuthUser
    let seedPhrase: String
    let seedHash: String?

    enum CodingKeys: String, CodingKey {
        case user
        case seedPhrase = "seed_phrase"
        case seedHash = "seed_hash"
    }
}

struct LoginRequest: Encodable {
    let seedPhrase: String

    enum CodingKeys: String, CodingKey {
        case seedPhrase = "seed_phrase"
    }
}

// MARK: - Auth Errors
enum AuthError: LocalizedError {
    case keychainError(String)
    case decodingError(Error)
    case networkError(String)
    case invalidSeedPhrase
    case userNotFound
    case seedPhraseNotFound
    case seedPhraseGenerationFailed
    case apiError(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .keychainError(let message):
            return "Keychain error: \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidSeedPhrase:
            return "Invalid seed phrase"
        case .userNotFound:
            return "User not found"
        case .seedPhraseNotFound:
            return "Seed phrase not found in Keychain"
        case .seedPhraseGenerationFailed:
            return "Failed to generate seed phrase"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Auth Service
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var userId: String?
    @Published var token: String?

    private let keychain = Keychain(service: "com.recipescaler.native")
    private let userDefaultsKey = "userId"
    private let tokenKey = "authToken"
    private let seedPhraseKey = "seedPhrase"

    private var apiClient: APIClient {
        APIClient.shared
    }

    private init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isUITesting = ProcessInfo.processInfo.arguments.contains("ui-testing")

        if isTesting || isUITesting {
            isAuthenticated = false
            userId = nil
            token = nil
            return
        }

        // Restore authentication state from storage
        restoreAuthenticationState()
    }

    // MARK: - Private Methods
    private func restoreAuthenticationState() {
        // Try to restore userId from UserDefaults
        if let restoredUserId = UserDefaults.standard.string(forKey: userDefaultsKey) {
            self.userId = restoredUserId
            self.isAuthenticated = true

            // Ignore any legacy tokens and use user id for auth
            self.token = nil
            deleteTokenFromUserDefaults()

            apiClient.configure(userId: restoredUserId)
        }
    }

    private func saveSeedPhraseToKeychain(_ seedPhrase: String) throws {
        do {
            try keychain.set(seedPhrase, key: seedPhraseKey)
        } catch {
            throw AuthError.keychainError("Failed to save seed phrase: \(error.localizedDescription)")
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
            throw AuthError.keychainError("Failed to retrieve seed phrase: \(error.localizedDescription)")
        }
    }

    private func saveUserIdToUserDefaults(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: userDefaultsKey)
    }

    private func saveTokenToUserDefaults(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    private func deleteSeedPhraseFromKeychain() throws {
        do {
            try keychain.remove(seedPhraseKey)
        } catch {
            throw AuthError.keychainError("Failed to delete seed phrase: \(error.localizedDescription)")
        }
    }

    private func deleteUserIdFromUserDefaults() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private func deleteTokenFromUserDefaults() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    private func buildAuthRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: "\(Config.baseURL)\(path)") else {
            throw AuthError.networkError("Invalid URL")
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorResponse["error"] ?? errorResponse["message"] {
                throw AuthError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            throw AuthError.apiError(statusCode: httpResponse.statusCode, message: "Request failed")
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
        let response: APIResponse<RegisterAutoResponse> = try await performAuthRequest(
            path: "/api/auth/register-auto",
            method: "POST"
        )

        guard response.success, let data = response.data else {
            throw AuthError.apiError(
                statusCode: 400,
                message: response.error ?? "Registration failed"
            )
        }

        // Save seed phrase to Keychain
        try saveSeedPhraseToKeychain(data.seedPhrase)

        // Save userId to UserDefaults
        saveUserIdToUserDefaults(data.user.id)
        deleteTokenFromUserDefaults()

        // Update published properties
        self.userId = data.user.id
        self.token = nil
        self.isAuthenticated = true

        // Configure API client with user id
        apiClient.configure(userId: data.user.id)

        return (userId: data.user.id, seedPhrase: data.seedPhrase, token: "")
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

        // Create login request
        let loginRequest = LoginRequest(seedPhrase: seedPhrase)
        let encoder = JSONEncoder()
        let body = try encoder.encode(loginRequest)

        let response: APIResponse<AuthResponse> = try await performAuthRequest(
            path: "/api/auth/login-with-seed",
            method: "POST",
            body: body
        )

        guard response.success, let data = response.data else {
            throw AuthError.apiError(
                statusCode: 400,
                message: response.error ?? "Login failed"
            )
        }

        // Save seed phrase to Keychain
        try saveSeedPhraseToKeychain(seedPhrase)

        // Save userId to UserDefaults
        saveUserIdToUserDefaults(data.user.id)
        deleteTokenFromUserDefaults()

        // Update published properties
        self.userId = data.user.id
        self.token = nil
        self.isAuthenticated = true

        // Configure API client with user id
        apiClient.configure(userId: data.user.id)

        return (userId: data.user.id, token: "")
    }

    /// Logout the current user
    func logout() throws {
        // Delete seed phrase from Keychain
        try deleteSeedPhraseFromKeychain()

        // Delete user data from UserDefaults
        deleteUserIdFromUserDefaults()
        deleteTokenFromUserDefaults()

        // Reset published properties
        self.userId = nil
        self.token = nil
        self.isAuthenticated = false

        // Reset API client
        apiClient.configure(authToken: nil)
        apiClient.configure(userId: nil)
    }

    /// Get the current authentication status
    var isAuthenticatedBool: Bool {
        return isAuthenticated
    }

    /// Retrieve the stored seed phrase from Keychain
    func getSeedPhrase() throws -> String {
        return try retrieveSeedPhraseFromKeychain()
    }
}
