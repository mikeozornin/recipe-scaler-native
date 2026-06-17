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

public final class APIClient: ObservableObject, @unchecked Sendable {
    public static let shared = APIClient()

    private let baseURL: String

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
    case serverError(message: String)
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
        case .serverError(let message):
            return message
        case .decodingError:
            return "api.error.decoding"
        case .unauthorized:
            return "api.error.unauthorized"
        }
    }
}
