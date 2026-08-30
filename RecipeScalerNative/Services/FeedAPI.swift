//
//  FeedAPI.swift
//  RecipeScalerNative
//
//  Spec 072 — personal feed, badge and the server-side seen marker.
//
//    GET  /api/v1/feed?cursor&limit  → { items, next_cursor, snapshot_at }
//    GET  /api/v1/feed/badge         → { has_new }
//    POST /api/v1/feed/seen          → 204, optional { seen_at: ISO }
//
//  `published_at` / `snapshot_at` are decoded as `String`: `requestJSON` uses
//  `JSONDecoder.dateDecodingStrategy = .iso8601`, which rejects the fractional
//  seconds Node's `toISOString()` always emits (see `SystemBannerDTO.createdAt`).
//

import Foundation
import RecipeScalerCore

/// Requested page size for every feed page (web `FEED_PAGE_SIZE`); the server
/// clamps to its max (default 20, max 100 — over-limit is clamped, not an error).
enum FeedAPI {
    static let pageSize = 100

    static func fetchPage(
        cursor: String?,
        api: APIClient = .shared
    ) async throws -> FeedPageDTO {
        var query = "limit=\(FeedAPI.pageSize)"
        if let cursor, !cursor.isEmpty {
            let encoded = cursor.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(.punctuationCharacters)
            ) ?? cursor
            query += "&cursor=\(encoded)"
        }
        let response: APIResponse<FeedPageDTO> = try await api.requestJSON(
            path: "/api/v1/feed?\(query)"
        )
        return try APIClient.unwrapResponse(response, fallback: .apiErrorServerGeneric)
    }

    static func fetchBadge(api: APIClient = .shared) async throws -> FeedBadgeDTO {
        let response: APIResponse<FeedBadgeDTO> = try await api.requestJSON(
            path: "/api/v1/feed/badge"
        )
        return try APIClient.unwrapResponse(response, fallback: .apiErrorServerGeneric)
    }

    /// Extinguish the badge. With `seenAt` — an echoed server `snapshot_at`
    /// from a successfully loaded page («прочитано = загружено»); without —
    /// server `now()`. The caller passes the snapshot only when it was
    /// actually returned by the server: client clocks are untrusted.
    static func markSeen(seenAt: String?, api: APIClient = .shared) async throws {
        struct EmptyData: Decodable {}
        let body: MarkSeenBody?
        if let seenAt, !seenAt.isEmpty {
            body = MarkSeenBody(seen_at: seenAt)
        } else {
            body = nil
        }
        let _: APIResponse<EmptyData>? = try await api.requestJSON(
            path: "/api/v1/feed/seen",
            method: "POST",
            body: body
        )
    }

    private struct MarkSeenBody: Encodable {
        let seen_at: String
    }
}

struct FeedEntryDTO: Decodable, Sendable, Equatable, Identifiable {
    let recipeId: String
    let username: String
    let displayName: String?
    /// Username-based avatar URL or null (server never returns storage paths).
    let avatarRef: String?
    /// Opaque image filename; feed cards resolve it via the image endpoints.
    let imageRef: String?
    let name: String
    let publishedAt: String
    /// Newer than the reader's seen marker at page-1 query time (server flag).
    let isNew: Bool

    var id: String { recipeId }

    init(
        recipeId: String,
        username: String,
        displayName: String?,
        avatarRef: String?,
        imageRef: String?,
        name: String,
        publishedAt: String,
        isNew: Bool
    ) {
        self.recipeId = recipeId
        self.username = username
        self.displayName = displayName
        self.avatarRef = avatarRef
        self.imageRef = imageRef
        self.name = name
        self.publishedAt = publishedAt
        self.isNew = isNew
    }

    enum CodingKeys: String, CodingKey {
        case recipeId = "recipe_id"
        case username
        case displayName = "display_name"
        case avatarRef = "avatar_ref"
        case imageRef = "image_ref"
        case name
        case publishedAt = "published_at"
        case isNew = "is_new"
    }
}

struct FeedPageDTO: Decodable, Sendable, Equatable {
    let items: [FeedEntryDTO]
    let nextCursor: String?
    /// Server time of the page query; echoed back by `markSeen`.
    let snapshotAt: String?
    /// Spec 072 wire contract (web feed.ts): `false` → «нет подписок» empty
    /// state. Absent from older servers → nil (treated as "unknown").
    let hasFollows: Bool?
    /// Reader's seen marker at query time; the client recomputes `isNew`
    /// against this cutoff on cursor pages (the server flag is only reliable
    /// on page 1, before the seen echo moves the marker).
    let lastSeenAt: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case snapshotAt = "snapshot_at"
        case hasFollows = "has_follows"
        case lastSeenAt = "last_seen_at"
    }
}

struct FeedBadgeDTO: Decodable, Sendable, Equatable {
    let hasNew: Bool

    enum CodingKeys: String, CodingKey {
        case hasNew = "has_new"
    }
}
