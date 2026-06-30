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
        DiscoverAPI.avatarURL(fromPublicProfile: relativeURL)
    }

    static func collectionRecipeCard(recipe: CuratedRecipeMetadataDTO) -> URL? {
        DiscoverAPI.collectionRecipeCardImageURL(recipe: recipe)
    }

    static func publicRecipeCard(recipe: PublicRecipePreviewDTO) -> URL? {
        DiscoverAPI.publicRecipeCardImageURL(recipe: recipe)
    }
}
