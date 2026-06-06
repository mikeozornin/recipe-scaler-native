//
//  RecipeImportAPI.swift
//  RecipeScalerNative
//

import Foundation
import UniformTypeIdentifiers

struct ImportRecipesResultDTO: Decodable, Sendable {
    let recipeIds: [String]
    let recipeId: String?
    let importedCount: Int
}

@MainActor
enum RecipeImportAPI {

    /// Import by URL(s). Matches the web `import-recipe-sheet.tsx` logic:
    /// `{ url }` for a single URL, `{ urls }` for many.
    static func importURLs(_ urls: [String]) async throws -> ImportRecipesResultDTO {
        precondition(!urls.isEmpty, "importURLs requires at least one URL")

        let body: AnyEncodable
        if urls.count == 1 {
            struct SingleBody: Encodable { let url: String }
            body = AnyEncodable(SingleBody(url: urls[0]))
        } else {
            struct MultiBody: Encodable { let urls: [String] }
            body = AnyEncodable(MultiBody(urls: urls))
        }

        let response: APIResponse<ImportRecipesResultDTO> = try await APIClient.shared.requestJSON(
            path: "/api/recipes/import/url",
            method: "POST",
            body: body
        )
        return try unwrap(response)
    }

    /// Convenience for a single URL.
    static func importURL(_ url: String) async throws -> ImportRecipesResultDTO {
        try await importURLs([url])
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

    /// Upload all provided images in a single multipart request, matching
    /// `recipeImportApi.importRecipeImages` on the web.
    static func importImages(_ items: [ImportPhotoItem]) async throws -> ImportRecipesResultDTO {
        guard !items.isEmpty else {
            throw APIError.serverError(message: "No images")
        }

        let files: [(fileName: String, data: Data, mimeType: String)] = items.map { item in
            (fileName: item.fileName, data: item.data, mimeType: mimeType(for: item.utType))
        }

        let data = try await APIClient.shared.uploadMultipart(
            path: "/api/recipes/import/image",
            fieldName: "images",
            files: files
        )
        let response = try JSONDecoder().decode(APIResponse<ImportRecipesResultDTO>.self, from: data)
        return try unwrap(response)
    }

    private static func unwrap<T>(_ response: APIResponse<T>) throws -> T {
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Import failed")
        }
        return data
    }

    private static func mimeType(for utType: UTType?) -> String {
        guard let utType else { return "image/jpeg" }
        if utType.conforms(to: .png) { return "image/png" }
        if utType.conforms(to: .webP) { return "image/webp" }
        if utType.conforms(to: .heic) { return "image/heic" }
        return "image/jpeg"
    }
}
