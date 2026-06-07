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

@MainActor
enum TelegramAPI {
    static func connect() async throws -> TelegramConnectionCodeDTO {
        struct EmptyBody: Encodable {}
        let response: APIResponse<TelegramConnectionCodeDTO> = try await APIClient.shared.requestJSON(
            path: "/api/telegram/connect",
            method: "POST",
            body: EmptyBody()
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? String(localized: "telegram.failed-to-get-code"))
        }
        return data
    }

    static func status() async throws -> TelegramConnectionStatusDTO {
        let response: APIResponse<TelegramConnectionStatusDTO> = try await APIClient.shared.requestJSON(
            path: "/api/telegram/status"
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Telegram status failed")
        }
        return data
    }

    static func disconnect() async throws {
        struct EmptyBody: Encodable {}
        let response: APIResponse<[String: String]> = try await APIClient.shared.requestJSON(
            path: "/api/telegram/disconnect",
            method: "POST",
            body: EmptyBody()
        )
        guard response.success else {
            throw APIError.serverError(message: response.error ?? String(localized: "telegram.failed-to-disconnect"))
        }
    }
}