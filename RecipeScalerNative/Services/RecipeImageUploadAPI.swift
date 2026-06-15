//
//  RecipeImageUploadAPI.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

struct RecipeImageUploadResult: Decodable, Sendable {
    let imageUrl: String
    let aspectRatio: Double?
}

@MainActor
enum RecipeImageUploadAPI {
    static func upload(recipeId: String, payload: RecipeImageUploadPayload) async throws -> RecipeImageUploadResult {
        let data = try await APIClient.shared.uploadMultipart(
            path: "/api/recipes/\(recipeId)/image",
            fieldName: "image",
            fileData: payload.data,
            fileName: payload.fileName,
            mimeType: payload.mimeType
        )
        let response = try JSONDecoder().decode(APIResponse<RecipeImageUploadResult>.self, from: data)
        guard response.success, let payload = response.data else {
            throw APIError.serverError(message: response.error ?? "Upload failed")
        }
        return payload
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