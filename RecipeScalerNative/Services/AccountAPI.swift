//
//  AccountAPI.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

// MARK: - DTOs

struct UserProfileDTO: Decodable, Sendable {
    let username: String?
    let name: String?
    let avatarUrl: String?
    let telegramUsername: String?
    let canChangeUsername: Bool?
    let profileUrl: String?
}

struct SharingSettingsDTO: Decodable, Sendable {
    let username: String?
    let publicProfileEnabled: Bool?
    let shareMode: String?
    let allowRecipeDownloads: Bool?
}

struct SharingSettingsPatchResponseDTO: Decodable, Sendable {
    let username: String?
    let name: String?
    let publicProfileEnabled: Bool?
    let shareMode: String?
    let allowRecipeDownloads: Bool?
}

struct UserSettingsDTO: Decodable, Sendable {
    let nutritionEnabled: Bool?
}

/// Feature-adoption report (spec 038). All 10 keys are always present in the
/// server payload; each is modeled as `Bool?` and treated as `false` when nil
/// via `value(for:)`. Snake_case JSON keys map to camelCase Swift properties.
struct FeatureAdoptionReportDTO: Decodable, Sendable {
    let installedNativeApp: Bool?
    let installedWatchApp: Bool?
    let importedRecipe: Bool?
    let createdRecipe: Bool?
    let createdCollection: Bool?
    let sharedRecipe: Bool?
    let connectedTelegram: Bool?
    let connectedMcpAssistant: Bool?
    let sentAssistantMessage: Bool?
    let usedShoppingList: Bool?

    enum CodingKeys: String, CodingKey {
        case installedNativeApp = "installed_native_app"
        case installedWatchApp = "installed_watch_app"
        case importedRecipe = "imported_recipe"
        case createdRecipe = "created_recipe"
        case createdCollection = "created_collection"
        case sharedRecipe = "shared_recipe"
        case connectedTelegram = "connected_telegram"
        case connectedMcpAssistant = "connected_mcp_assistant"
        case sentAssistantMessage = "sent_assistant_message"
        case usedShoppingList = "used_shopping_list"
    }

    func value(for item: FeatureAdoptionItem) -> Bool {
        switch item {
        case .installedNativeApp: return installedNativeApp ?? false
        case .installedWatchApp: return installedWatchApp ?? false
        case .importedRecipe: return importedRecipe ?? false
        case .createdRecipe: return createdRecipe ?? false
        case .createdCollection: return createdCollection ?? false
        case .sharedRecipe: return sharedRecipe ?? false
        case .connectedTelegram: return connectedTelegram ?? false
        case .connectedMcpAssistant: return connectedMcpAssistant ?? false
        case .sentAssistantMessage: return sentAssistantMessage ?? false
        case .usedShoppingList: return usedShoppingList ?? false
        }
    }
}

enum PublicShareMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case with_images_and_steps
    case one_by_one

    var id: String { rawValue }

    init?(apiValue: String?) {
        guard let apiValue, let mode = PublicShareMode(rawValue: apiValue) else { return nil }
        self = mode
    }
}

// MARK: - API

enum AccountAPI {
    static func fetchProfile() async throws -> UserProfileDTO {
        let response: APIResponse<UserProfileDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/profile"
        )
        return try APIClient.unwrapResponse(response, fallback: .accountProfileLoadFailed)
    }

    static func fetchSharingSettings() async throws -> SharingSettingsDTO {
        let response: APIResponse<SharingSettingsDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/sharing-settings"
        )
        return try APIClient.unwrapResponse(response, fallback: .accountSharingLoadFailed)
    }

    static func patchSharingSettings(
        publicProfileEnabled: Bool? = nil,
        shareMode: PublicShareMode? = nil,
        allowRecipeDownloads: Bool? = nil
    ) async throws -> SharingSettingsPatchResponseDTO {
        struct Body: Encodable {
            var publicProfileEnabled: Bool?
            var shareMode: String?
            var allowRecipeDownloads: Bool?

            enum CodingKeys: String, CodingKey {
                case publicProfileEnabled
                case shareMode
                case allowRecipeDownloads
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(publicProfileEnabled, forKey: .publicProfileEnabled)
                try container.encodeIfPresent(shareMode, forKey: .shareMode)
                try container.encodeIfPresent(allowRecipeDownloads, forKey: .allowRecipeDownloads)
            }
        }
        let response: APIResponse<SharingSettingsPatchResponseDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/sharing-settings",
            method: "PATCH",
            body: Body(
                publicProfileEnabled: publicProfileEnabled,
                shareMode: shareMode?.rawValue,
                allowRecipeDownloads: allowRecipeDownloads
            )
        )
        return try APIClient.unwrapResponse(response, fallback: .accountSharingUpdateFailed)
    }

    static func patchDisplayName(_ name: String) async throws {
        struct Body: Encodable { let name: String }
        let _: APIResponse<UserProfileDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/name",
            method: "PATCH",
            body: Body(name: name)
        )
    }

    static func updateUsername(_ username: String) async throws {
        struct Body: Encodable { let username: String }
        let _: APIResponse<UserProfileDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/username",
            method: "PUT",
            body: Body(username: username)
        )
    }

    static func uploadAvatar(imageData: Data) async throws {
        _ = try await APIClient.shared.uploadMultipart(
            path: "/api/users/avatar",
            fieldName: "avatar",
            fileData: imageData,
            fileName: "avatar.jpg",
            mimeType: "image/jpeg"
        )
    }

    static func deleteAvatar() async throws {
        let _: APIResponse<[String: String]> = try await APIClient.shared.requestJSON(
            path: "/api/users/avatar",
            method: "DELETE"
        )
    }

    static func fetchUserSettings() async throws -> UserSettingsDTO {
        let response: APIResponse<UserSettingsDTO> = try await APIClient.shared.requestJSON(
            path: "/api/settings"
        )
        return try APIClient.unwrapResponse(response, fallback: .accountSettingsLoadFailed)
    }

    static func updateNutritionEnabled(_ enabled: Bool) async throws {
        struct Body: Encodable {
            let nutrition_enabled: Bool
        }
        let _: APIResponse<UserSettingsDTO> = try await APIClient.shared.requestJSON(
            path: "/api/settings",
            method: "PUT",
            body: Body(nutrition_enabled: enabled)
        )
    }

    static func logoutDevice(userId: String, deviceId: String) async {
        struct Body: Encodable {
            let user_id: String
            let device_id: String
        }
        let _: APIResponse<[String: String]>? = try? await APIClient.shared.requestJSON(
            path: "/api/auth/logout",
            method: "POST",
            body: Body(user_id: userId, device_id: deviceId)
        )
    }

    // MARK: - Feature adoption (spec 038)

    static func fetchFeatureAdoption() async throws -> FeatureAdoptionReportDTO {
        let response: APIResponse<FeatureAdoptionReportDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/me/feature-adoption"
        )
        return try APIClient.unwrapResponse(response, fallback: .accountProfileLoadFailed)
    }

    /// Idempotent: server applies `INSERT ... ON CONFLICT DO NOTHING`.
    static func markFeatureAdoption(_ feature: FeatureAdoptionClientFeature) async throws {
        try await FeatureAdoptionAPI.markFeatureAdoption(feature)
    }
}
