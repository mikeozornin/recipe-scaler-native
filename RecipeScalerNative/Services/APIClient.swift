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

struct RecipeListResponse: Decodable {
    let recipes: [RecipeDTO]
}

// MARK: - Data Transfer Objects
struct RecipeDTO: Decodable {
    let id: String
    let name: String
    let description: String?
    let originalRecipeLink: String?
    let color: String?
    let scaleFactor: Double?
    let originalRecipe: String?
    let imageUrl: String?
    let createdAt: String
    let updatedAt: String
    let userId: String?
    let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, description, color
        case originalRecipeLink = "original_recipe_link"
        case scaleFactor = "scale_factor"
        case originalRecipe = "original_recipe"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
        case isPublic = "is_public"
    }
}

struct IngredientDTO: Decodable {
    let id: String
    let name: String
    let originalAmount: Double?
    let unit: String
    let order: Int
    let isSeparator: Bool?
    let calories: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let weight: Double?
}

// Full recipe with ingredients and description (from format=human endpoint)
struct RecipeFullDTO: Decodable {
    let id: String
    let name: String
    let imageUrl: String?
    let scaleFactor: Double
    let ingredients: [IngredientFullDTO]
    let text: String?  // HTML description
    let timers: [TimerDTO]?
    let originalRecipeLink: String?
}

struct IngredientFullDTO: Decodable {
    let id: String
    let name: String
    let originalAmount: Double?
    let scaledAmount: Double?
    let unit: String
    let isSeparator: Bool?
}

struct TimerDTO: Decodable {
    let id: String
    let name: String
    let duration: Int  // in seconds
    let type: String  // "hours", "minutes", "seconds"
    let originalText: String
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
    func recipeImageURL(id: String, preview: Bool) -> URL? {
        var components = URLComponents(string: "\(baseURL)/api/recipes/\(id)/image")
        if preview {
            components?.queryItems = [URLQueryItem(name: "preview", value: "true")]
        }
        return components?.url
    }

    // MARK: - Request Builder
    private func buildRequest(
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

    // MARK: - Recipes API
    func fetchRecipes() async throws -> [RecipeDTO] {
        let response = try await fetchRecipesCached(etag: nil, lastModified: nil)
        guard response.statusCode == 200, let recipes = response.data else {
            throw APIError.serverError(message: "Unexpected response status: \(response.statusCode)")
        }
        return recipes
    }

    func fetchRecipesCached(etag: String?, lastModified: String?) async throws -> CachedAPIResponse<[RecipeDTO]> {
        var headers: [String: String] = [:]
        if let etag, !etag.isEmpty {
            headers["If-None-Match"] = etag
        } else if let lastModified, !lastModified.isEmpty {
            headers["If-Modified-Since"] = lastModified
        }

        let request = try buildRequest(path: "/api/v1/recipes", headers: headers)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let statusCode = httpResponse.statusCode
        let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag")
        let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        if statusCode == 304 {
            #if DEBUG
            print("[APIClient] GET /api/v1/recipes 304 Not Modified, ETag: \(responseEtag ?? etag ?? "nil")")
            #endif
            return CachedAPIResponse(
                statusCode: statusCode,
                etag: responseEtag ?? etag,
                lastModified: responseLastModified ?? lastModified,
                data: nil
            )
        }

        guard (200...299).contains(statusCode) else {
            throw APIError.httpError(statusCode: statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let apiResponse = try decoder.decode(APIResponse<[RecipeDTO]>.self, from: data)

        guard apiResponse.success, let recipes = apiResponse.data else {
            throw APIError.serverError(message: apiResponse.error ?? "Unknown error")
        }

        return CachedAPIResponse(
            statusCode: statusCode,
            etag: responseEtag,
            lastModified: responseLastModified,
            data: recipes
        )
    }

    func fetchRecipe(id: String) async throws -> RecipeDTO {
        let response: APIResponse<RecipeDTO> = try await performRequest(
            path: "/api/v1/recipes/\(id)"
        )

        guard response.success, let recipe = response.data else {
            throw APIError.serverError(message: response.error ?? "Unknown error")
        }

        return recipe
    }

    func searchRecipes(query: String, limit: Int = 50) async throws -> [RecipeDTO] {
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        var urlComponents = URLComponents(string: "\(baseURL)/api/v1/recipes/search")
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let userId = userId {
            request.setValue(userId, forHTTPHeaderField: "x-user-id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        struct SearchResponse: Decodable {
            struct SearchData: Decodable {
                let recipes: [RecipeDTO]
            }
            let success: Bool
            let data: SearchData?
        }

        let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
        return searchResponse.data?.recipes ?? []
    }

    /// Fetch full recipe with ingredients and description
    func fetchRecipeFull(id: String, scaleFactor: Double = 1.0) async throws -> RecipeFullDTO {
        let response = try await fetchRecipeFullCached(id: id, scaleFactor: scaleFactor, etag: nil, lastModified: nil)
        guard response.statusCode == 200, let recipe = response.data else {
            throw APIError.serverError(message: "Unexpected response status: \(response.statusCode)")
        }
        return recipe
    }

    func fetchRecipeFullCached(
        id: String,
        scaleFactor: Double = 1.0,
        etag: String?,
        lastModified: String?
    ) async throws -> CachedAPIResponse<RecipeFullDTO> {
        var urlComponents = URLComponents(string: "\(baseURL)/api/recipes/\(id)")
        urlComponents?.queryItems = [
            URLQueryItem(name: "format", value: "human"),
            URLQueryItem(name: "scale_factor", value: "\(scaleFactor)")
        ]

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var headers: [String: String] = [:]
        if let etag, !etag.isEmpty {
            headers["If-None-Match"] = etag
        } else if let lastModified, !lastModified.isEmpty {
            headers["If-Modified-Since"] = lastModified
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let userId = userId {
            request.setValue(userId, forHTTPHeaderField: "x-user-id")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let statusCode = httpResponse.statusCode
        let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag")
        let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        if statusCode == 304 {
            #if DEBUG
            print("[APIClient] GET /api/recipes/\(id)?format=human 304 Not Modified, ETag: \(responseEtag ?? etag ?? "nil")")
            #endif
            return CachedAPIResponse(
                statusCode: statusCode,
                etag: responseEtag ?? etag,
                lastModified: responseLastModified ?? lastModified,
                data: nil
            )
        }

        guard (200...299).contains(statusCode) else {
            throw APIError.httpError(statusCode: statusCode)
        }

        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(APIResponse<RecipeFullDTO>.self, from: data)

        guard apiResponse.success, let recipe = apiResponse.data else {
            throw APIError.serverError(message: apiResponse.error ?? "Unknown error")
        }

        return CachedAPIResponse(
            statusCode: statusCode,
            etag: responseEtag,
            lastModified: responseLastModified,
            data: recipe
        )
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
