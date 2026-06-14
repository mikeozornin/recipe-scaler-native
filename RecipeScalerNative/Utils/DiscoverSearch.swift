//
//  DiscoverSearch.swift
//  RecipeScalerNative
//

import Foundation

/// Search helper for Discover entities. Reuses `RecipeSearchUtils` tokenization
/// (NFKD + diacritics + quoted phrases + AND semantics per `search-behavior.mdc`)
/// so behavior matches the rest of the app.
enum DiscoverSearch {
    /// Returns `true` if every token occurs in at least one of the provided fields.
    /// Empty tokens → matches everything.
    static func matchesAnyField(tokens: [String], fields: [String?]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let normalizedFields = fields.compactMap { $0 }.map(RecipeSearchUtils.normalizeForSearch)
        guard !normalizedFields.isEmpty else { return false }
        return tokens.allSatisfy { token in
            normalizedFields.contains { $0.contains(token) }
        }
    }

    /// Tokenize a query string using project-wide rules.
    static func tokenize(_ query: String) -> [String] {
        RecipeSearchUtils.tokenizeQuery(query)
    }
}

extension Array where Element == CuratedRecipeMetadataDTO {
    func filtered(by query: String) -> [CuratedRecipeMetadataDTO] {
        let tokens = DiscoverSearch.tokenize(query)
        guard !tokens.isEmpty else { return self }
        return filter { recipe in
            DiscoverSearch.matchesAnyField(
                tokens: tokens,
                fields: [recipe.name]
            )
        }
    }
}

extension Array where Element == PublicRecipePreviewDTO {
    func filtered(by query: String) -> [PublicRecipePreviewDTO] {
        let tokens = DiscoverSearch.tokenize(query)
        guard !tokens.isEmpty else { return self }
        return filter { recipe in
            DiscoverSearch.matchesAnyField(
                tokens: tokens,
                fields: [recipe.name, recipe.description]
            )
        }
    }
}

extension Array where Element == DiscoveryCollectionDTO {
    func filtered(by query: String) -> [DiscoveryCollectionDTO] {
        let tokens = DiscoverSearch.tokenize(query)
        guard !tokens.isEmpty else { return self }
        return filter { collection in
            DiscoverSearch.matchesAnyField(
                tokens: tokens,
                fields: [collection.title, collection.description, collection.authorName]
            )
        }
    }
}

extension Array where Element == PublicProfilePreviewDTO {
    func filtered(by query: String) -> [PublicProfilePreviewDTO] {
        let tokens = DiscoverSearch.tokenize(query)
        guard !tokens.isEmpty else { return self }
        return filter { profile in
            DiscoverSearch.matchesAnyField(
                tokens: tokens,
                fields: [profile.name, profile.username, profile.description]
            )
        }
    }
}
