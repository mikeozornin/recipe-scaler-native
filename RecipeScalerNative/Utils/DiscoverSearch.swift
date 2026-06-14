//
//  DiscoverSearch.swift
//  RecipeScalerNative
//

import Foundation
import SwiftUI

/// Searchable item exposed to `DiscoverSearchStore`.
///
/// Each item provides one or more plain-text fields. The store normalizes them
/// once and reuses the cache across queries.
protocol DiscoverSearchable: Identifiable, Sendable {
    var id: String { get }
    var searchFields: [String?] { get }
}

extension CuratedRecipeMetadataDTO: DiscoverSearchable {
    var searchFields: [String?] { [name] }
}

extension PublicRecipePreviewDTO: DiscoverSearchable {
    var searchFields: [String?] { [name, description] }
}

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

    /// A–Z by display name (leading emoji ignored), same as web `compareRecipeNamesIgnoringLeadingEmoji`.
    static func sortedByRecipeName<Item>(_ items: [Item], name: (Item) -> String?) -> [Item] {
        items.sorted { lhs, rhs in
            RecipeTitleEmoji.compareNames(name(lhs), name(rhs)) == .orderedAscending
        }
    }
}

/// Background search store for Discover lists.
///
/// - Normalizes searchable fields once when items are set.
/// - Debounces queries and cancels stale filtering work.
/// - Runs the actual token matching off the main actor so the search bar stays
///   responsive while typing.
/// - Publishes a single `filteredSnapshot` for the view to read.
@MainActor
@Observable
final class DiscoverSearchStore<Item: DiscoverSearchable> {
    private(set) var filteredSnapshot: [Item] = []

    private var allItems: [Item] = []
    private var normalizedFieldsById: [String: [String]] = [:]
    private var currentQuery: String = ""
    private var queryGeneration: UInt64 = 0
    private var debounceTask: Task<Void, Never>?
    private let debounceMs: UInt64 = 120

    /// Replace the source list and rebuild the normalized-field cache.
    func setItems(_ items: [Item]) {
        allItems = items
        normalizedFieldsById = [:]
        normalizedFieldsById.reserveCapacity(items.count)
        for item in items {
            normalizedFieldsById[item.id] = item.searchFields
                .compactMap { $0 }
                .map(RecipeSearchUtils.normalizeForSearch)
        }
        applyQuery(currentQuery, debounce: false)
    }

    /// Update the search query. The snapshot is updated after a short debounce.
    func setQuery(_ query: String) {
        currentQuery = query
        queryGeneration += 1
        applyQuery(query, debounce: true)
    }

    private func applyQuery(_ query: String, debounce: Bool) {
        debounceTask?.cancel()

        let tokens = RecipeSearchUtils.tokenizeQuery(query)
        guard !tokens.isEmpty else {
            filteredSnapshot = allItems
            return
        }

        let generation = queryGeneration
        let shouldDebounce = debounce

        debounceTask = Task { [weak self] in
            guard let self else { return }
            if shouldDebounce {
                try? await Task.sleep(for: .milliseconds(self.debounceMs))
            }
            guard !Task.isCancelled else { return }

            let start = Date()
            let result = await Task.detached(priority: .userInitiated) { [items = self.allItems, normalized = self.normalizedFieldsById, tokens] in
                items.filter { item in
                    guard let fields = normalized[item.id], !fields.isEmpty else { return false }
                    return tokens.allSatisfy { token in
                        fields.contains { $0.contains(token) }
                    }
                }
            }.value
            let ms = Date().timeIntervalSince(start) * 1000

            await MainActor.run {
                guard generation == self.queryGeneration else { return }
                self.filteredSnapshot = result
                #if DEBUG
                AgentSyncDebugLog.write(
                    hypothesisId: "discover-search-perf",
                    location: "DiscoverSearchStore.applyQuery",
                    message: "discover_search_filter",
                    data: [
                        "discover_search_filter_ms": String(format: "%.2f", ms),
                        "itemCount": "\(self.allItems.count)",
                        "resultCount": "\(result.count)"
                    ]
                )
                #endif
            }
        }
    }
}
