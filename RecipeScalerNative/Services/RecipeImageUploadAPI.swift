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

enum ImportedRecipeImageUploadError: Error {
    case preprocessingFailed
}

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
        return try APIClient.unwrapResponse(response, fallback: .recipeImageUploadFailed)
    }

    static func delete(recipeId: String) async throws {
        let response: APIResponse<[String: String]> = try await APIClient.shared.requestJSON(
            path: "/api/recipes/\(recipeId)/image",
            method: "DELETE"
        )
        guard response.success else {
            let code = ServerErrorCode.from(
                serverValue: response.error,
                fallback: .recipeImageDeleteFailed
            )
            throw APIError.serverError(code: code)
        }
    }
}
