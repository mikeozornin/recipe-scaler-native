//
//  APIClient.swift
//  RecipeScalerNative
//
//

import Foundation

// MARK: - API Response Models
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
}

struct CachedAPIResponse<T> {
    let statusCode: Int
    let etag: String?
    let lastModified: String?
    let data: T?
}

// MARK: - API Client
@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    private let baseURL: String
    private var authToken: String?
    private var userId: String?

    private init() {
        self.baseURL = Config.baseURL
    }

    // MARK: - Configuration
    func configure(authToken: String?) {
        self.authToken = authToken
    }

    func configure(userId: String?) {
        self.userId = userId
    }

    // MARK: - Image URL Helpers
    func recipeImageURL(id: String, preview: Bool, version: String? = nil) -> URL? {
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
    func recipeImageDownloadRequest(
        remoteURL: URL,
        etag: String?,
        lastModified: String?
    ) -> URLRequest {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let userId = userId {
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
    func buildRequest(
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

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let userId = userId {
            request.setValue(userId, forHTTPHeaderField: "x-user-id")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = body
        return request
    }

    // MARK: - Generic Request
    private func performRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        let request = try buildRequest(path: path, method: method, body: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Nutrition Recalculation
    func calculateNutrition(recipeId: String) async throws {
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
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case serverError(message: String)
    case decodingError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized access"
        }
    }
}
