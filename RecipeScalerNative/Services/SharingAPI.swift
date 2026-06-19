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

enum SharingAPI {
    static func fetchShoppingListSettings() async throws -> ShoppingListShareSettings {
        let response: APIResponse<ShoppingListShareSettings> = try await APIClient.shared.requestJSON(
            path: "/api/v1/shopping-list/settings"
        )
        return try APIClient.unwrapResponse(response, fallback: .sharingUpdateFailed)
    }

    static func updateShoppingListShare(enabled: Bool) async throws -> ShoppingListShareSettings {
        struct Body: Encodable { let share_enabled: Bool }
        let response: APIResponse<ShoppingListShareSettings> = try await APIClient.shared.requestJSON(
            path: "/api/v1/shopping-list/share",
            method: "PUT",
            body: Body(share_enabled: enabled)
        )
        return try APIClient.unwrapResponse(response, fallback: .sharingUpdateFailed)
    }
}
