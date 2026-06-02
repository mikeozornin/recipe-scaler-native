//
//  DiscoverAPI.swift
//  RecipeScalerNative
//

import Foundation

struct DiscoveryCollectionDTO: Decodable, Identifiable, Sendable {
    var id: String { slug }
    let slug: String
    let title: String
    let description: String?
    let author_name: String?
    let cover_image_url: String?
    let recipe_count: Int
}

struct PublicProfilePreviewDTO: Decodable, Identifiable, Sendable {
    var id: String { username }
    let username: String
    let name: String?
    let avatar_url: String?
    let recipe_count: Int
    let description: String?
}

struct DiscoveryDataDTO: Decodable, Sendable {
    let collections: [DiscoveryCollectionDTO]
    let profiles: [PublicProfilePreviewDTO]
}

struct CuratedRecipeMetadataDTO: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let image_url: String?
    let color: String
}

struct CollectionWithRecipesDTO: Decodable, Sendable {
    let slug: String
    let title: String
    let description: String?
    let author_name: String?
    let recipes: [CuratedRecipeMetadataDTO]
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
    let image_url: String?
    let color: String
    let source_url: String?
    let prep_time_minutes: Int?
    let cook_time_minutes: Int?
    let servings: Int?
}

struct CloneRecipeResultDTO: Decodable, Sendable {
    let recipeId: String
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

    static func discoverImageURL(recipeId: String) -> URL? {
        URL(string: "\(Config.baseURL)/api/discover/recipes/\(recipeId)/image")
    }
}