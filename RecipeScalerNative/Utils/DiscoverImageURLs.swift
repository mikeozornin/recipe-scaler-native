//
//  DiscoverImageURLs.swift
//  RecipeScalerNative
//

import Foundation

/// URL builders for Discover UI. Keeps `DiscoverAPI` out of view code.
enum DiscoverImageURLs {
    static func collectionCover(from coverImageURL: String?) -> URL? {
        DiscoverAPI.collectionCoverURL(from: coverImageURL)
    }

    static func avatar(username: String, preview: Bool = true) -> URL? {
        DiscoverAPI.avatarURL(username: username, preview: preview)
    }

    static func avatar(fromPublicProfile relativeURL: String?) -> URL? {
        avatarPreviewURL(DiscoverAPI.avatarURL(fromPublicProfile: relativeURL))
    }

    /// Web `Avatar.appendPreviewAndVersion` parity: server serves the square
    /// `preview.webp` only when `preview=true`; without it the portrait original
    /// is returned and `scaledToFill` in a 24pt frame looks over-zoomed.
    static func avatarPreviewURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        var queryItems = components.queryItems ?? []
        if let index = queryItems.firstIndex(where: { $0.name == "preview" }) {
            queryItems[index].value = "true"
        } else {
            queryItems.append(URLQueryItem(name: "preview", value: "true"))
        }
        components.queryItems = queryItems
        return components.url ?? url
    }

    static func collectionRecipeCard(recipe: CuratedRecipeMetadataDTO) -> URL? {
        DiscoverAPI.collectionRecipeCardImageURL(recipe: recipe)
    }

    static func publicRecipeCard(recipe: PublicRecipePreviewDTO) -> URL? {
        DiscoverAPI.publicRecipeCardImageURL(recipe: recipe)
    }
}
