//
//  RecipeImageCacheStatus.swift
//  RecipeScalerNative
//

import Foundation

/// Aggregated on-disk cache state for recipe images (preview + full).
struct RecipeImageCacheStatus: Equatable, Sendable {
    var recipesWithImage: Int = 0
    var previewCached: Int = 0
    var fullCached: Int = 0
    var isDownloading: Bool = false
    var downloadCompleted: Int = 0
    var downloadTotal: Int = 0

    var isFullyCached: Bool {
        recipesWithImage == 0 || fullCached >= recipesWithImage
    }

    var pendingFullCount: Int {
        max(0, recipesWithImage - fullCached)
    }

    /// Entries that still need a full image file (for the status sheet).
    var pendingEntries: [RecipeImageCachePendingEntry] = []
}

struct RecipeImageCachePendingEntry: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let missingPreview: Bool
    let missingFull: Bool
}

extension Notification.Name {
    static let recipeImageCacheStatusDidChange = Notification.Name("recipeImageCacheStatusDidChange")
    static let recipeImagePrefetchDidUpdate = Notification.Name("recipeImagePrefetchDidUpdate")
}