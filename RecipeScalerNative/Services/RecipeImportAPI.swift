//
//  RecipeImportAPI.swift
//  RecipeScalerNative
//

import Foundation

struct ImportRecipesResultDTO: Decodable, Sendable {
    let recipeIds: [String]
    let recipeId: String?
    let importedCount: Int
}

@MainActor
enum RecipeImportAPI {
    static func importURL(_ url: String) async throws -> ImportRecipesResultDTO {
        struct Body: Encodable { let url: String }
        let response: APIResponse<ImportRecipesResultDTO> = try await APIClient.shared.requestJSON(
            path: "/api/recipes/import/url",
            method: "POST",
            body: Body(url: url)
        )
        return try unwrap(response)
    }

    static func importText(_ text: String) async throws -> ImportRecipesResultDTO {
        struct Body: Encodable { let text: String }
        let response: APIResponse<ImportRecipesResultDTO> = try await APIClient.shared.requestJSON(
            path: "/api/recipes/import/text",
            method: "POST",
            body: Body(text: text)
        )
        return try unwrap(response)
    }

    static func importImages(_ imagesData: [Data], fileNames: [String]) async throws -> ImportRecipesResultDTO {
        // Single-image path uses first file; multi-image uses combined endpoint.
        guard let first = imagesData.first else {
            throw APIError.serverError(message: "No images")
        }
        let name = fileNames.first ?? "image.jpg"
        let data = try await APIClient.shared.uploadMultipart(
            path: "/api/recipes/import/image",
            fieldName: "images",
            fileData: first,
            fileName: name,
            mimeType: "image/jpeg"
        )
        let decoder = JSONDecoder()
        let response = try decoder.decode(APIResponse<ImportRecipesResultDTO>.self, from: data)
        return try unwrap(response)
    }

    private static func unwrap<T>(_ response: APIResponse<T>) throws -> T {
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Import failed")
        }
        return data
    }
}