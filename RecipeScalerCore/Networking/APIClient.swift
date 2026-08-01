//
//  APIClient.swift
//  RecipeScalerCore
//
//  Non-isolated HTTP client shared between the main app and extensions.
//
//  Originally `@MainActor`; lifted to `nonisolated` so that Share/Action extensions
//  (which do not have a main actor by default) can reuse the same code paths.
//  Concurrent access to `authToken` / `userId` is guarded by `Mutex` (iOS 17+).
//

import Foundation
import os

// MARK: - API Response Models

public struct APIResponse<T: Decodable>: Decodable {
    public let success: Bool
    public let data: T?
    public let error: String?
}

public struct CachedAPIResponse<T> {
    public let statusCode: Int
    public let etag: String?
    public let lastModified: String?
    public let data: T?

    public init(statusCode: Int, etag: String?, lastModified: String?, data: T?) {
        self.statusCode = statusCode
        self.etag = etag
        self.lastModified = lastModified
        self.data = data
    }
}

// MARK: - API Client

public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    private let baseURL: String

    /// Spec 055 Phase R: central 401 interceptor. Set by `AppContainer.init`
    /// (main app only — extensions leave this `nil`). When any authenticated
    /// REST call returns 401, `notifyUnauthorizedIfNeeded(statusCode:)` fires
    /// the handler so `AuthService.handleDeviceTokenInvalid()` can run seed
    /// exchange recovery (web parity with `fetchWithAuth` /
    /// `handleAuthFailureResponse` in `auth-session-revoked.ts`).
    ///
    /// The handler is `@Sendable` because `APIClient` is `nonisolated`. The
    /// closure is expected to hop to `MainActor` itself — `APIClient` does
    /// not synchronise on any actor and must not block the calling thread.
    ///
    /// Reads/writes are guarded by `handlerLock` so the "set once from
    /// `AppContainer.init`" contract is enforced even if a test or a future
    /// module reassigns the handler concurrently with a 401 in flight.
    public var unauthorizedHandler: (@Sendable () async -> Void)? {
        get { handlerLock.withLock { $0 } }
        set { handlerLock.withLock { $0 = newValue } }
    }
    private let handlerLock = OSAllocatedUnfairLock(initialState: Optional<(@Sendable () async -> Void)>.none)

    /// Mutex-guarded mutable auth state. Reads/writes from any thread are safe.
    private struct AuthState {
        var authToken: String?
        var userId: String?
    }
    private let authLock = OSAllocatedUnfairLock(initialState: AuthState(authToken: nil, userId: nil))

    private init() {
        self.baseURL = Config.baseURL
    }

    // MARK: - Configuration

    public func configure(authToken: String?) {
        authLock.withLock { $0.authToken = authToken }
    }

    public func configure(userId: String?) {
        authLock.withLock { $0.userId = userId }
    }

    // MARK: - Spec 055 Phase R: unauthorized interceptor

    /// Fire `unauthorizedHandler` when an authenticated response came back 401.
    /// No-op when the handler isn't installed (Share/Action extensions, previews,
    /// tests). The handler runs in a detached `Task` so the caller's request
    /// path is not blocked — the 401 is still thrown to the caller as usual.
    public func notifyUnauthorizedIfNeeded(statusCode: Int) {
        guard statusCode == 401 else { return }
        guard let handler = unauthorizedHandler else { return }
        Task { await handler() }
    }

    // MARK: - Image URL Helpers

    public func recipeImageURL(id: String, preview: Bool, version: String? = nil) -> URL? {
        var components = URLComponents(string: "\(baseURL)/api/recipes/\(id)/image")
        var queryItems: [URLQueryItem] = []
        if preview {
            queryItems.append(URLQueryItem(name: "preview", value: "true"))
        }
        if let version, !version.isEmpty {
            queryItems.append(URLQueryItem(name: "v", value: version))
        }
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url
    }

    /// Builds an authenticated GET for recipe image bytes (used by `ImageCacheService`).
    public func recipeImageDownloadRequest(
        remoteURL: URL,
        etag: String?,
        lastModified: String?
    ) -> URLRequest {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let snapshot = authLock.withLock { $0 }
        if let token = snapshot.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let userId = snapshot.userId {
            request.setValue(userId, forHTTPHeaderField: "x-user-id")
        }
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        } else if let lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        return request
    }

    // MARK: - Request Builder

    public func buildRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let snapshot = authLock.withLock { $0 }
        if let token = snapshot.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let userId = snapshot.userId {
            request.setValue(userId, forHTTPHeaderField: "x-user-id")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = body
        return request
    }

    // MARK: - Nutrition Recalculation

    public func calculateNutrition(recipeId: String) async throws {
        let request = try buildRequest(
            path: "/api/recipes/\(recipeId)/calculate-nutrition",
            method: "POST"
        )

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - API Errors

public enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case serverError(code: ServerErrorCode)
    case decodingError(Error)
    case unauthorized

    /// Returns a dot-key identifier for each fixed case. The Native target resolves
    /// these via `Bundle.currentLocalizedString` (see `APIError+Localization.swift`).
    /// `serverError(message:)` returns the message as-is — the contract is that the
    /// server supplies a dot-key (see `specs/031-error-i18n/server-error-keys.md`).
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "api.error.invalid-url"
        case .invalidResponse:
            return "api.error.invalid-response"
        case .httpError(let code):
            return "api.error.http:\(code)"
        case .serverError(let code):
            return code.rawValue
        case .decodingError:
            return "api.error.decoding"
        case .unauthorized:
            return "api.error.unauthorized"
        }
    }
}
