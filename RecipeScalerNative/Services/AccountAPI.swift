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
}
