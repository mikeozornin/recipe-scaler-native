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
    public static func markFeatureAdoption(_ feature: String) async throws {
        struct Body: Encodable { let feature: String }
        struct MarkResponse: Decodable { let recorded: Bool? }
        let _: APIResponse<MarkResponse> = try await APIClient.shared.requestJSON(
            path: "/api/users/me/feature-adoption",
            method: "POST",
            body: Body(feature: feature)
        )
    }
}
