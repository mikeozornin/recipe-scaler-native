//
//  FollowAPI.swift
//  RecipeScalerNative
//
//  Spec 072 — author follow endpoints (wire contract: web spec 072 § Wire-контракт).
//
//    POST   /api/v1/users/:username/follow      → subscribe (idempotent)
//    DELETE /api/v1/users/:username/follow      → unsubscribe (idempotent 204)
//    PATCH  /api/v1/users/:username/follow      → { push_opt_in } bell toggle
//    GET    /api/v1/users/me/following/:username → follow status
//

import Foundation
import RecipeScalerCore

struct FollowStatusDTO: Decodable, Sendable, Equatable {
    let following: Bool
    let pushOptIn: Bool

    enum CodingKeys: String, CodingKey {
        case following
        case pushOptIn = "push_opt_in"
    }
}

enum FollowAPI {
    static func follow(username: String, api: APIClient = .shared) async throws {
        struct EmptyData: Decodable {}
        let _: APIResponse<EmptyData> = try await api.requestJSON(
            path: "/api/v1/users/\(Self.encoded(username))/follow",
            method: "POST"
        )
    }

    static func unfollow(username: String, api: APIClient = .shared) async throws {
        struct EmptyData: Decodable {}
        let _: APIResponse<EmptyData> = try await api.requestJSON(
            path: "/api/v1/users/\(Self.encoded(username))/follow",
            method: "DELETE"
        )
    }

    static func setPushOptIn(
        username: String,
        pushOptIn: Bool,
        api: APIClient = .shared
    ) async throws -> FollowStatusDTO {
        struct Body: Encodable { let push_opt_in: Bool }
        let response: APIResponse<FollowStatusDTO> = try await api.requestJSON(
            path: "/api/v1/users/\(Self.encoded(username))/follow",
            method: "PATCH",
            body: Body(push_opt_in: pushOptIn)
        )
        return try APIClient.unwrapResponse(response, fallback: .followNotFollowing)
    }

    static func fetchStatus(
        username: String,
        api: APIClient = .shared
    ) async throws -> FollowStatusDTO {
        let response: APIResponse<FollowStatusDTO> = try await api.requestJSON(
            path: "/api/v1/users/me/following/\(Self.encoded(username))"
        )
        return try APIClient.unwrapResponse(response, fallback: .followUserNotFound)
    }

    private static func encoded(_ username: String) -> String {
        username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
    }
}
