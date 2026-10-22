//
//  AliceAPI.swift
//  RecipeScalerNative
//
//  Web spec 066 (US11): pairing code for the Alice skill «Книга рецептов».
//  The user types the code on the skill sign-in page or says it to Alice.
//  Server: `recipe-scaler-web/server/src/routes/alice.ts`. Pattern: `TelegramAPI`.
//

import Foundation
import RecipeScalerCore

/// `POST /api/alice/connect` → `data`: 8-digit one-time code, TTL 10 minutes.
struct AliceConnectionCodeDTO: Decodable, Sendable, Equatable {
    let code: String
    let expiresInMinutes: Int?
}

/// `GET /api/alice/status` → `data`. Dates are ISO 8601 strings, absent when not connected.
struct AliceConnectionStatusDTO: Decodable, Sendable, Equatable {
    let connected: Bool
    let connectedAt: String?
    let lastActiveAt: String?
}

enum AliceAPI {
    static func connect() async throws -> AliceConnectionCodeDTO {
        try await withFallback(.aliceFailedToGetCode) {
            let response: APIResponse<AliceConnectionCodeDTO> = try await APIClient.shared.requestJSON(
                path: "/api/alice/connect",
                method: "POST",
                body: EmptyBody()
            )
            return try APIClient.unwrapResponse(response, fallback: .aliceFailedToGetCode)
        }
    }

    static func status() async throws -> AliceConnectionStatusDTO {
        try await withFallback(.aliceFailedToGetStatus) {
            let response: APIResponse<AliceConnectionStatusDTO> = try await APIClient.shared.requestJSON(
                path: "/api/alice/status"
            )
            return try APIClient.unwrapResponse(response, fallback: .aliceFailedToGetStatus)
        }
    }

    /// Unlinks every Yandex account of the user and revokes the skill's OAuth grants.
    static func disconnect() async throws {
        try await withFallback(.aliceFailedToDisconnect) {
            let response: APIResponse<[String: String]> = try await APIClient.shared.requestJSON(
                path: "/api/alice/disconnect",
                method: "POST",
                body: EmptyBody()
            )
            guard response.success else {
                let code = ServerErrorCode.from(
                    serverValue: response.error,
                    fallback: .aliceFailedToDisconnect
                )
                throw APIError.serverError(code: code)
            }
        }
    }

    private struct EmptyBody: Encodable {}

    /// The Alice routes answer 5xx with English text (`"Failed to get status"`),
    /// which `APIClient` surfaces as `.upstreamMessage` and the UI would render
    /// as an import error. Collapse those into the endpoint's dot-key; keep
    /// `.unauthorized`, body-less 4xx and transport errors as they are.
    static func withFallback<T>(
        _ fallback: ServerErrorCode,
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch APIError.upstreamMessage(let message) {
            throw APIError.serverError(code: ServerErrorCode.from(serverValue: message, fallback: fallback))
        } catch APIError.httpError(let statusCode) where (500...599).contains(statusCode) {
            throw APIError.serverError(code: fallback)
        }
    }
}
