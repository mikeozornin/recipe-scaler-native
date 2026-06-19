//
//  RecipeLLMParseAPI.swift
//  RecipeScalerNative
//
//  LLM "Auto-detect recipe" endpoint (019 US7 / 018 US1).
//  Web contract: `recipe-scaler-web/recipe-scaler/src/pages/recipe-detail.tsx` `runParseWithLLM`
//  → `POST /api/v1/recipes/{id}/parse` body `{ stepsText, apply: true }`, header `X-User-ID`.
//
//  When `apply: true`, the server applies the LLM result to the Yjs document itself and
//  emits `recipe_updated` + `collection_updated` + `document_loaded` over WebSocket — the
//  native sync layer (YjsSyncService) picks these up like any other remote change.
//  Server response shape: `{ success: true, yjsState: [...], lastSyncedAt: ISO }` (NOT wrapped
//  in our `APIResponse<T>` envelope), so we call URLSession directly.
//

import Foundation
import RecipeScalerCore

enum RecipeLLMParseAPI {
    enum LLMParseError: Error {
        case emptyDescription
        case server(message: String)
    }

    private struct ParseBody: Encodable {
        let stepsText: String
        let apply: Bool
    }

    private struct ServerErrorBody: Decodable {
        let error: String?
    }

    /// `POST /api/v1/recipes/{id}/parse` with `apply: true`.
    /// Server applies the LLM result; sync delivers updates. Caller just needs success/failure.
    /// - Parameter language: optional `X-App-Language` header value (e.g. `"ru"`, `"en"`).
    static func parseAndApply(recipeId: String, stepsHtml: String, language: String? = nil) async throws {
        let trimmed = stepsHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMParseError.emptyDescription }

        var headers: [String: String] = [:]
        if let language { headers["X-App-Language"] = language }
        let bodyData = try JSONEncoder().encode(ParseBody(stepsText: stepsHtml, apply: true))
        let request = try APIClient.shared.buildRequest(
            path: "/api/v1/recipes/\(recipeId)/parse",
            method: "POST",
            body: bodyData,
            headers: headers
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMParseError.server(message: "")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.error
            throw LLMParseError.server(message: message ?? "")
        }
        // Server has applied changes and emitted recipe_updated / collection_updated /
        // document_loaded over WebSocket — YjsSyncService picks them up automatically.
    }
}
