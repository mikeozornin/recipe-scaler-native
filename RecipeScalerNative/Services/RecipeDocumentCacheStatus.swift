//
//  RecipeDocumentCacheStatus.swift
//  RecipeScalerNative
//

import Foundation

/// Aggregated on-disk Y.Doc cache state for recipe bodies (ingredients, description, …).
struct RecipeDocumentCacheStatus: Equatable, Sendable {
    var totalRecipes: Int = 0
    var cachedRecipes: Int = 0
    var isDownloading: Bool = false
    var downloadCompleted: Int = 0
    var downloadTotal: Int = 0

    var isFullyCached: Bool {
        totalRecipes == 0 || cachedRecipes >= totalRecipes
    }

    var pendingCount: Int {
        max(0, totalRecipes - cachedRecipes)
    }

    var pendingEntries: [RecipeDocumentCachePendingEntry] = []
}

struct RecipeDocumentCachePendingEntry: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}