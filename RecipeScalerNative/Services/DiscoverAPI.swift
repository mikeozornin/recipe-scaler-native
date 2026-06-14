//
//  DiscoverAPI.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

struct DiscoveryCollectionDTO: Decodable, Identifiable, Sendable {
    var id: String { slug }
    let slug: String
    let title: String
    let description: String?
    let authorName: String?
    let coverImageURL: String?
    let recipeCount: Int

    private enum CodingKeys: String, CodingKey {
        case slug, title, description
        case authorName = "author_name"
        case coverImageURL = "cover_image_url"
        case recipeCount = "recipe_count"
    }
}

/// Preview of a public profile as returned by `/api/discover/collections`.
/// The server returns `avatar_url` as a *raw storage path* (e.g.
/// `cfcd839f.../avatar/original.webp`) — **not** a usable URL. iOS builds the
/// avatar URL via `DiscoverAPI.avatarURL(username:)` and ignores this field.
struct PublicProfilePreviewDTO: Decodable, Identifiable, Sendable {
    var id: String { username }
    let username: String
    let name: String?
    let avatarURL: String?
    let recipeCount: Int
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case username, name, description
        case avatarURL = "avatar_url"
        case recipeCount = "recipe_count"
    }
}

struct DiscoveryDataDTO: Decodable, Sendable {
    let collections: [DiscoveryCollectionDTO]
    let profiles: [PublicProfilePreviewDTO]
}

/// Recipe preview as listed inside a collection or a public profile.
/// `imageURL` is a raw storage path, not a usable URL — use
/// `DiscoverAPI.recipeImageURL(recipeId:)` instead.
struct CuratedRecipeMetadataDTO: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let imageURL: String?
    let color: String

    private enum CodingKeys: String, CodingKey {
        case id, name, color
        case imageURL = "image_url"
    }
}

struct CollectionWithRecipesDTO: Decodable, Sendable {
    let slug: String
    let title: String
    let description: String?
    let authorName: String?
    let recipes: [CuratedRecipeMetadataDTO]

    private enum CodingKeys: String, CodingKey {
        case slug, title, description, recipes
        case authorName = "author_name"
    }
}

/// Public recipe state from `GET /api/v2/recipes/public/{id}/state`. Returns
/// ready-to-use metadata (name, color, imageUrl) plus a binary `yjsState` update
/// that must be applied to a fresh `Y.Doc` to read ingredients/description.
struct PublicRecipeStateDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let color: String?
    let imageUrl: String?
    let username: String?
    let createdAt: Date?
    let updatedAt: Date?
    /// Yjs v1 state update (array of bytes).
    let yjsState: [Int]?
}

struct CuratedRecipeDTO: Decodable, Identifiable, Sendable {
    struct IngredientDTO: Decodable, Sendable {
        let name: String
        let amount: Double?
        let unit: String
    }

    let id: String
    let name: String
    let description: String?
    let ingredients: [IngredientDTO]
    let imageURL: String?
    let color: String
    let sourceURL: String?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let servings: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, ingredients, color, servings
        case imageURL = "image_url"
        case sourceURL = "source_url"
        case prepTimeMinutes = "prep_time_minutes"
        case cookTimeMinutes = "cook_time_minutes"
    }
}

struct CloneRecipeResultDTO: Decodable, Sendable {
    let recipeId: String
}

/// How a public profile exposes its recipes. Mirrors web `ShareMode`.
enum PublicProfileShareMode: String, Decodable, Sendable {
    case oneByOne = "one_by_one"
    case all
    case withImagesAndSteps = "with_images_and_steps"
}

/// Full public profile from `GET /api/users/public/:username` — server response
/// is camelCase (`avatarUrl`, `recipeCount`, `allowRecipeDownloads`, `shareMode`).
struct PublicProfileDTO: Decodable, Identifiable, Sendable {
    var id: String { username }
    let username: String
    let name: String?
    /// Ready-to-use relative URL like `/api/users/{username}/avatar?preview=true&v=...`.
    /// Use `DiscoverAPI.avatarURL(fromPublicProfile:)` to resolve to absolute.
    let avatarUrl: String?
    let recipeCount: Int
    let description: String?
    let allowRecipeDownloads: Bool?
    let shareMode: PublicProfileShareMode?
}

struct PublicRecipePreviewDTO: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    /// Raw storage path (not usable) — use `DiscoverAPI.recipeImageURL(recipeId:)`.
    let imageUrl: String?
    let color: String?
    let createdAt: Date?
}

struct PublicProfileResponseDTO: Decodable, Sendable {
    let profile: PublicProfileDTO
    let recipes: [PublicRecipePreviewDTO]
}

@MainActor
enum DiscoverAPI {
    static func fetchDiscovery() async throws -> DiscoveryDataDTO {
        let response: APIResponse<DiscoveryDataDTO> = try await APIClient.shared.requestJSON(
            path: "/api/discover/collections"
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Discover fetch failed")
        }
        return data
    }

    static func fetchCollection(slug: String) async throws -> CollectionWithRecipesDTO {
        let response: APIResponse<CollectionWithRecipesDTO> = try await APIClient.shared.requestJSON(
            path: "/api/discover/collections/\(slug)"
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Collection fetch failed")
        }
        return data
    }

    static func fetchRecipe(id: String) async throws -> CuratedRecipeDTO {
        let response: APIResponse<CuratedRecipeDTO> = try await APIClient.shared.requestJSON(
            path: "/api/discover/recipes/\(id)"
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Recipe fetch failed")
        }
        return data
    }

    static func cloneRecipe(id: String) async throws -> String {
        struct Body: Encodable { let locale: String }
        let response: APIResponse<CloneRecipeResultDTO> = try await APIClient.shared.requestJSON(
            path: "/api/discover/recipes/\(id)/clone",
            method: "POST",
            body: Body(locale: Locale.current.language.languageCode?.identifier ?? "en")
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Clone failed")
        }
        return data.recipeId
    }

    /// Fetch a public recipe state: top-level metadata (name, color, imageUrl)
    /// plus a Yjs v1 state update (`yjsState`) for ingredients/description.
    /// Public profiles use this endpoint — `GET /api/discover/recipes/:id`
    /// only works for curated recipes.
    static func fetchPublicRecipeState(id: String) async throws -> PublicRecipeStateDTO {
        let request = try APIClient.shared.buildRequest(
            path: "/api/v2/recipes/public/\(id)/state",
            method: "GET",
            body: nil,
            headers: [:]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let d = DiscoverDateParser.parse(s) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO8601 date: \(s)"
            )
        }
        do {
            let wrapped = try decoder.decode(APIResponse<PublicRecipeStateDTO>.self, from: data)
            guard wrapped.success, let payload = wrapped.data else {
                throw APIError.serverError(message: wrapped.error ?? "Public recipe fetch failed")
            }
            return payload
        } catch let error as DecodingError {
            throw APIError.serverError(message: "Public recipe decode failed: \(error)")
        }
    }

    /// Copy a public recipe into the current user's account (web `copyRecipe`).
    /// Returns the new local recipe ID.
    static func copyRecipe(id: String) async throws -> String {
        let response: APIResponse<CloneRecipeResultDTO> = try await APIClient.shared.requestJSON(
            path: "/api/v2/recipes/\(id)/copy",
            method: "POST"
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Copy failed")
        }
        return data.recipeId
    }

    static func fetchPublicProfile(username: String) async throws -> PublicProfileResponseDTO {
        let encoded = username.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? username
        let request = try APIClient.shared.buildRequest(
            path: "/api/users/public/\(encoded)",
            method: "GET",
            body: nil,
            headers: [:]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let d = DiscoverDateParser.parse(s) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO8601 date: \(s)"
            )
        }
        do {
            let wrapped = try decoder.decode(APIResponse<PublicProfileResponseDTO>.self, from: data)
            guard wrapped.success, let payload = wrapped.data else {
                throw APIError.serverError(message: wrapped.error ?? "Public profile fetch failed")
            }
            return payload
        } catch let error as DecodingError {
            throw APIError.serverError(message: "Public profile decode failed: \(error)")
        }
    }

    // MARK: - Image URLs

    /// Curated recipe image for discover collection grids
    /// (web `/api/discover/recipes/:id/image`, `aspect-video object-cover`).
    static func discoverRecipeImageURL(recipeId: String) -> URL? {
        URL(string: "\(Config.baseURL)/api/discover/recipes/\(recipeId)/image")
    }

    /// Public recipe image. Same endpoint as for private recipes —
    /// server serves it without auth for discoverable recipes.
    /// `preview=true` returns a smaller variant; grids use `preview: false` (web parity).
    static func recipeImageURL(recipeId: String, preview: Bool = true) -> URL? {
        URL(string: "\(Config.baseURL)/api/recipes/\(recipeId)/image\(preview ? "?preview=true" : "")")
    }

    static func collectionRecipeCardImageURL(recipe: CuratedRecipeMetadataDTO) -> URL? {
        guard let imageURL = recipe.imageURL, !imageURL.isEmpty else { return nil }
        return discoverRecipeImageURL(recipeId: recipe.id)
    }

    static func publicRecipeCardImageURL(recipe: PublicRecipePreviewDTO) -> URL? {
        guard let imageURL = recipe.imageUrl, !imageURL.isEmpty else { return nil }
        return recipeImageURL(recipeId: recipe.id, preview: false)
    }

    /// Public avatar for a `username` (preview variant is smaller).
    static func avatarURL(username: String, preview: Bool = true) -> URL? {
        URL(string: "\(Config.baseURL)/api/users/\(username)/avatar\(preview ? "?preview=true" : "")")
    }

    /// Resolve the `avatarUrl` field returned by `GET /api/users/public/:username`.
    /// Server returns a ready-to-use relative URL (e.g.
    /// `/api/users/{username}/avatar?preview=true&v=...`); we just attach the host.
    static func avatarURL(fromPublicProfile relativeURL: String?) -> URL? {
        guard let relativeURL, !relativeURL.isEmpty else { return nil }
        if let absolute = URL(string: relativeURL), absolute.scheme != nil {
            return absolute
        }
        let separator = relativeURL.hasPrefix("/") ? "" : "/"
        return URL(string: "\(Config.baseURL)\(separator)\(relativeURL)")
    }

    /// Cover image for a curated collection. Server returns a raw storage path
    /// in `cover_image_url`; we currently don't have a usable proxy, so this
    /// returns `nil` for relative paths (placeholder is shown instead).
    static func collectionCoverURL(from coverImageURL: String?) -> URL? {
        guard let coverImageURL, !coverImageURL.isEmpty else { return nil }
        if let absolute = URL(string: coverImageURL), absolute.scheme != nil {
            return absolute
        }
        return nil
    }
}

/// Tolerant ISO8601 parser — accepts both `2025-09-12T11:29:08.641+00:00`
/// (server format with fractional seconds) and `2025-09-12T11:29:08Z`
/// (standard). Swift's built-in `.iso8601` strategy rejects fractional seconds.
enum DiscoverDateParser {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String) -> Date? {
        withFractionalSeconds.date(from: string)
            ?? withoutFractionalSeconds.date(from: string)
    }
}
