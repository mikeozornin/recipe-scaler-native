//
//  TelegramAPI.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

struct TelegramConnectionCodeDTO: Decodable, Sendable {
    let code: String
    let instructions: String
}

struct TelegramConnectionStatusDTO: Decodable, Sendable {
    let connected: Bool
    let telegramUsername: String?
    let connectedAt: String?
}

enum TelegramAPI {
    static func connect() async throws -> TelegramConnectionCodeDTO {
        struct EmptyBody: Encodable {}
        let response: APIResponse<TelegramConnectionCodeDTO> = try await APIClient.shared.requestJSON(
            path: "/api/telegram/connect",
            method: "POST",
            body: EmptyBody()
        )
        return try APIClient.unwrapResponse(response, fallback: .telegramFailedToGetCode)
    }

    static func status() async throws -> TelegramConnectionStatusDTO {
        let response: APIResponse<TelegramConnectionStatusDTO> = try await APIClient.shared.requestJSON(
            path: "/api/telegram/status"
        )
        return try APIClient.unwrapResponse(response, fallback: .telegramStatusFailed)
    }

    static func disconnect() async throws {
        struct EmptyBody: Encodable {}
        let response: APIResponse<[String: String]> = try await APIClient.shared.requestJSON(
            path: "/api/telegram/disconnect",
            method: "POST",
            body: EmptyBody()
        )
        guard response.success else {
            let code = ServerErrorCode.from(
                serverValue: response.error,
                fallback: .telegramFailedToDisconnect
            )
            throw APIError.serverError(code: code)
        }
    }
}
