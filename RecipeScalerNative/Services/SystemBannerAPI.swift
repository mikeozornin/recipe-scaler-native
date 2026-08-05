//
//  SystemBannerAPI.swift
//  RecipeScalerNative
//
//  Spec 061 — system banner over the recipe list.
//
//  Two endpoints:
//    GET  /api/v1/system-banner/active    → server returns the one active banner
//                                            not dismissed by this user, or null.
//    POST /api/v1/system-banner/:id/dismiss → idempotent per-user dismissal.
//

import Foundation
import RecipeScalerCore

/// Wire DTO for the active system banner. Matches the snake_case server shape.
///
/// `created_at` is kept as `String` (ISO 8601) rather than `Date`: `APIClient.requestJSON`
/// uses `JSONDecoder.dateDecodingStrategy = .iso8601`, which rejects fractional
/// seconds (`…09.999Z`) that Node's `Date.toISOString()` always emits. Decoding
/// as `String` avoids a silent refresh failure that left the banner blank.
struct SystemBannerDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: UUID
    let titleEn: String
    let titleRu: String
    let bodyEn: String
    let bodyRu: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case titleEn = "title_en"
        case titleRu = "title_ru"
        case bodyEn = "body_en"
        case bodyRu = "body_ru"
        case createdAt = "created_at"
    }

    /// Picks the title for the current UI language (`"ru"` or `"en"`).
    func title(for languageCode: String) -> String {
        languageCode.hasPrefix("ru") ? titleRu : titleEn
    }

    /// Picks the body for the current UI language (`"ru"` or `"en"`).
    func body(for languageCode: String) -> String {
        languageCode.hasPrefix("ru") ? bodyRu : bodyEn
    }
}

enum SystemBannerAPI {
    /// Fetch the currently active banner not dismissed by the current user.
    /// Returns `nil` when there is no active banner or the user has dismissed it.
    ///
    /// The server returns `{ "success": true, "data": null }` when there is no
    /// banner to show. `APIClient.unwrapResponse` treats `data == nil` as a
    /// failure, so we decode the envelope manually and distinguish the
    /// `data: null` case from a real server error.
    static func fetchActive() async throws -> SystemBannerDTO? {
        let response: APIResponse<SystemBannerDTO> = try await APIClient.shared.requestJSON(
            path: "/api/v1/system-banner/active"
        )
        guard response.success else {
            throw APIError.serverError(code: .apiErrorServerGeneric)
        }
        return response.data
    }

    /// Idempotent per-user dismissal. Server-side `INSERT … ON CONFLICT DO NOTHING`.
    /// Never throws a UI-blocking error — the caller (store) treats failures as
    /// best-effort and will simply re-fetch the next session.
    static func dismiss(bannerId: UUID) async throws {
        struct EmptyResponse: Decodable {}
        let _: APIResponse<EmptyResponse> = try await APIClient.shared.requestJSON(
            path: "/api/v1/system-banner/\(bannerId.uuidString)/dismiss",
            method: "POST"
        )
    }
}
