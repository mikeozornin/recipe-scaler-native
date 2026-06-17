//
//  SharingAPI.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

struct ShoppingListShareSettings: Decodable, Sendable {
    let public_id: String?
    let share_enabled: Bool
}

@MainActor
enum SharingAPI {
    static func fetchShoppingListSettings() async -> ShoppingListShareSettings? {
        let response: APIResponse<ShoppingListShareSettings>? = try? await APIClient.shared.requestJSON(
            path: "/api/v1/shopping-list/settings"
        )
        return response?.data
    }

    static func updateShoppingListShare(enabled: Bool) async throws -> ShoppingListShareSettings {
        struct Body: Encodable { let share_enabled: Bool }
        let response: APIResponse<ShoppingListShareSettings> = try await APIClient.shared.requestJSON(
            path: "/api/v1/shopping-list/share",
            method: "PUT",
            body: Body(share_enabled: enabled)
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "sharing.update-failed")
        }
        return data
    }
}