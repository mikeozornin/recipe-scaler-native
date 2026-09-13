import Foundation
import RecipeScalerCore

/// `POST /api/recipes/:id/rebuild-process-table` — waits for LLM + Yjs patch.
enum ProcessTableAPI {
    private struct EmptyData: Decodable, Sendable {}

    static func rebuild(recipeId: String) async throws {
        let response: APIResponse<EmptyData> = try await APIClient.shared.requestJSON(
            path: "/api/recipes/\(recipeId)/rebuild-process-table",
            method: "POST",
            timeoutInterval: APIClient.llmRequestTimeout
        )
        guard response.success else {
            throw APIError.serverError(code: .apiErrorServerGeneric)
        }
    }
}
