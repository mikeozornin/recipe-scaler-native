//
//  FeatureAdoptionAPI.swift
//  RecipeScalerCore
//
//  Shared client for POST /api/users/me/feature-adoption (spec 038).
//  Used by the iOS app (via AccountAPI) and watchOS (WatchFeatureAdoptionReporter).
//

import Foundation

public enum FeatureAdoptionAPI {
    /// Idempotent: server applies `INSERT ... ON CONFLICT DO NOTHING`.
    ///
    /// Pass `userId` when the caller must pin auth for the whole request (watch session
    /// guards are not enough — `APIClient` reads its global snapshot at request build time).
    public static func markFeatureAdoption(
        _ feature: FeatureAdoptionClientFeature,
        userId: String? = nil
    ) async throws {
        struct Body: Encodable { let feature: String }
        struct MarkResponse: Decodable { let recorded: Bool? }

        var headers: [String: String] = [:]
        if let userId {
            headers["x-user-id"] = userId
        }

        let response: APIResponse<MarkResponse> = try await APIClient.shared.requestJSON(
            path: "/api/users/me/feature-adoption",
            method: "POST",
            body: Body(feature: feature.rawValue),
            extraHeaders: headers
        )
        _ = try APIClient.unwrapResponse(response, fallback: .authErrorApiGeneric)
    }
}
