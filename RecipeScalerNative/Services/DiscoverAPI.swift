//
//  DiscoverAPI.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

enum DiscoverRecipeImageSource: Hashable, Sendable {
    case curatedDiscover
    case publicRecipe
}

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

struct PublicRecipeStateDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let color: String?
    let imageUrl: String?
    let username: String?
    let createdAt: Date?
    let updatedAt: Date?
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

enum PublicProfileShareMode: String, Decodable, Sendable {
    case oneByOne = "one_by_one"
    case all
    case withImagesAndSteps = "with_images_and_steps"
}

struct PublicProfileDTO: Decodable, Identifiable, Sendable {
    var id: String { username }
    let username: String
    let name: String?
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
    let imageUrl: String?
    let color: String?
    let createdAt: Date?
}

struct PublicProfileResponseDTO: Decodable, Sendable {
    let profile: PublicProfileDTO
    let recipes: [PublicRecipePreviewDTO]
}

enum DiscoverAPI {
    static func fetchDiscovery() async throws -> DiscoveryDataDTO {
        let response: APIResponse<DiscoveryDataDTO> = try await APIClient.shared.requestJSON(
            path: "/api/discover/collections"
        )
        return try APIClient.unwrapResponse(response, fallback: .discoverFetchFailed)
    }

    static func fetchCollection(slug: String) async throws -> CollectionWithRecipesDTO {
        let response: APIResponse<CollectionWithRecipesDTO> = try await APIClient.shared.requestJSON(
            path: "/api/discover/collections/\(slug)"
        )
        return try APIClient.unwrapResponse(response, fallback: .discoverCollectionFailed)
    }

    static func fetchRecipe(id: String) async throws -> CuratedRecipeDTO {
        let response: APIResponse<CuratedRecipeDTO> = try await APIClient.shared.requestJSON(
            path: "/api/discover/recipes/\(id)"
        )
        return try APIClient.unwrapResponse(response, fallback: .discoverRecipeFailed)
    }

    static func cloneRecipe(id: String) async throws -> String {
        struct Body: Encodable { let locale: String }
        let response: APIResponse<CloneRecipeResultDTO> = try await APIClient.shared.requestJSON(
            path: "/api/discover/recipes/\(id)/clone",
            method: "POST",
            body: Body(locale: Locale.current.language.languageCode?.identifier ?? "en")
        )
        return try APIClient.unwrapResponse(response, fallback: .discoverCloneFailed).recipeId
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
            return try APIClient.unwrapResponse(wrapped, fallback: .discoverPublicRecipeFailed)
        } catch let error as DecodingError {
            AppLog.error(.document, "discover_public_recipe_decode_failed", data: ["error": "\(error)"])
            throw APIError.serverError(code: .discoverPublicRecipeFailed)
        }
    }

    /// Copy a public recipe into the current user's account (web `copyRecipe`).
    /// Returns the new local recipe ID.
    static func copyRecipe(id: String) async throws -> String {
        let response: APIResponse<CloneRecipeResultDTO> = try await APIClient.shared.requestJSON(
            path: "/api/v2/recipes/\(id)/copy",
            method: "POST"
        )
        return try APIClient.unwrapResponse(response, fallback: .discoverCopyFailed).recipeId
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
            return try APIClient.unwrapResponse(wrapped, fallback: .discoverPublicProfileFailed)
        } catch let error as DecodingError {
            AppLog.error(.document, "discover_public_profile_decode_failed", data: ["error": "\(error)"])
            throw APIError.serverError(code: .discoverPublicProfileFailed)
        }
    }

    // MARK: - Image URLs

    static func discoverRecipeImageURL(recipeId: String) -> URL? {
        URL(string: "\(Config.baseURL)/api/discover/recipes/\(recipeId)/image")
    }

    static func recipeImageURL(recipeId: String, preview: Bool = true) -> URL? {
        URL(string: "\(Config.baseURL)/api/recipes/\(recipeId)/image\(preview ? "?preview=true" : "")")
    }

    static func detailImageURL(recipeId: String, imageSource: DiscoverRecipeImageSource) -> URL? {
        switch imageSource {
        case .curatedDiscover:
            discoverRecipeImageURL(recipeId: recipeId)
        case .publicRecipe:
            recipeImageURL(recipeId: recipeId, preview: false)
        }
    }

    static func collectionRecipeCardImageURL(recipe: CuratedRecipeMetadataDTO) -> URL? {
        guard let imageURL = recipe.imageURL, !imageURL.isEmpty else { return nil }
        return discoverRecipeImageURL(recipeId: recipe.id)
    }

    static func publicRecipeCardImageURL(recipe: PublicRecipePreviewDTO) -> URL? {
        guard let imageURL = recipe.imageUrl, !imageURL.isEmpty else { return nil }
        return recipeImageURL(recipeId: recipe.id, preview: false)
    }

    static func avatarURL(username: String, preview: Bool = true) -> URL? {
        URL(string: "\(Config.baseURL)/api/users/\(username)/avatar\(preview ? "?preview=true" : "")")
    }

    static func avatarURL(fromPublicProfile relativeURL: String?) -> URL? {
        guard let relativeURL, !relativeURL.isEmpty else { return nil }
        if let absolute = URL(string: relativeURL), absolute.scheme != nil {
            return absolute
        }
        let separator = relativeURL.hasPrefix("/") ? "" : "/"
        return URL(string: "\(Config.baseURL)\(separator)\(relativeURL)")
    }

    static func collectionCoverURL(from coverImageURL: String?) -> URL? {
        guard let coverImageURL, !coverImageURL.isEmpty else { return nil }
        if let absolute = URL(string: coverImageURL), absolute.scheme != nil {
            return absolute
        }
        return nil
    }
}

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
