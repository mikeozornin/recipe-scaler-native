//
//  AccountAPI.swift
//  RecipeScalerNative
//

import Foundation

struct UserProfileDTO: Decodable, Sendable {
    let display_name: String?
    let avatar_url: String?
    let username: String?
}

struct PublicProfileSettingsDTO: Decodable, Sendable {
    let enabled: Bool?
    let username: String?
    let share_mode: String?
}

@MainActor
enum AccountAPI {
    static func patchDisplayName(_ name: String) async throws {
        struct Body: Encodable { let name: String }
        let _: APIResponse<UserProfileDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/name",
            method: "PATCH",
            body: Body(name: name)
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
}