//
//  RecipeImageUploadAPI.swift
//  RecipeScalerNative
//

import Foundation

struct RecipeImageUploadResult: Decodable, Sendable {
    let imageUrl: String
    let aspectRatio: Double?
}

@MainActor
enum RecipeImageUploadAPI {
    static func upload(recipeId: String, imageData: Data, fileName: String = "photo.jpg") async throws -> RecipeImageUploadResult {
        let data = try await APIClient.shared.uploadMultipart(
            path: "/api/recipes/\(recipeId)/image",
            fieldName: "image",
            fileData: imageData,
            fileName: fileName,
            mimeType: "image/jpeg"
        )
        let response = try JSONDecoder().decode(APIResponse<RecipeImageUploadResult>.self, from: data)
        guard response.success, let payload = response.data else {
            throw APIError.serverError(message: response.error ?? "Upload failed")
        }
        return payload
    }

    static func uploadFromURL(recipeId: String, imageURL: String) async throws -> RecipeImageUploadResult {
        struct Body: Encodable { let imageUrl: String }
        let response: APIResponse<RecipeImageUploadResult> = try await APIClient.shared.requestJSON(
            path: "/api/recipes/\(recipeId)/image-from-url",
            method: "POST",
            body: Body(imageUrl: imageURL)
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Upload failed")
        }
        return data
    }

    static func delete(recipeId: String) async throws {
        let response: APIResponse<[String: String]> = try await APIClient.shared.requestJSON(
            path: "/api/recipes/\(recipeId)/image",
            method: "DELETE"
        )
        guard response.success else {
            throw APIError.serverError(message: response.error ?? "Delete failed")
        }
        await RecipeImageService.shared.removeCache(recipeId: recipeId)
    }
}