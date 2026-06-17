import Foundation
import SwiftUI

/// Pre-built highlight payload for a single recipe row in the search list.
///
/// `title` is always highlighted (name matches or just normal rendering during
/// search). `snippet` is non-nil only for content matches (ingredient or
/// description), carrying the highlighted snippet string. Both are pre-built
/// `AttributedString`s so `RecipeRow.body` never rebuilds them on re-render.
struct RecipeRowHighlight: Equatable {
    let title: AttributedString
    let snippet: AttributedString?
}

/// Background recipe loader + highlight/snippet cache for the recipe list search.
///
/// Owns the full search snapshot so the view can read precomputed values:
/// - `filteredSnapshot` — the sorted, filtered `[CollectionEntry]` to render
/// - `highlights` — pre-built `RecipeRowHighlight` per recipe id
/// - `normalizedNames` — cached NFKD-normalized names, avoiding re-normalization
///   of the same name on every re-render
///
/// Each call to `refresh` cancels the previous load, so typing stays responsive.
/// Snapshot and highlights are published together via two property writes; SwiftUI
/// coalesces them within the same render pass.
@MainActor
@Observable
final class RecipeListSearchStore {
    private(set) var filteredSnapshot: [CollectionEntry] = []
    private(set) var highlights: [String: RecipeRowHighlight] = [:]

    /// Cached `normalizeForSearch(name)` per recipe id. Names are immutable for a
    /// given id, so this persists across queries.
    private var normalizedNames: [String: String] = [:]
    /// Loaded lightweight search projections, keyed by id. Persists across queries.
    private(set) var loadedSearchIndexes: [String: RecipeSearchIndex] = [:]
    /// Whether search is currently active (non-empty token list).
    private(set) var isActive: Bool = false

    private var loadTask: Task<Void, Never>?
    private weak var syncService: YjsSyncService?

    func bind(syncService: YjsSyncService) {
        self.syncService = syncService
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        filteredSnapshot = []
        highlights = [:]
        normalizedNames = [:]
        loadedSearchIndexes = [:]
        isActive = false
    }

    /// Recompute the search snapshot for `entries` against `query`.
    ///
    /// Synchronously publishes the name-match subset of the snapshot (so the UI
    /// updates instantly on every keystroke), then kicks off a cancellable
    /// background load of up to 100 name-miss recipes via `peekSearchIndex`,
    /// merging content matches into the snapshot as they resolve.
    func refresh(entries: [CollectionEntry], query: String) {
        loadTask?.cancel()

        let tokens = RecipeSearchUtils.tokenizeQuery(query)
        guard !tokens.isEmpty else {
            // Clear search state.
            filteredSnapshot = []
            highlights = [:]
            isActive = false
            return
        }

        isActive = true

        // Ensure every entry has a cached normalized name.
        for entry in entries where normalizedNames[entry.id] == nil {
            normalizedNames[entry.id] = RecipeSearchUtils.normalizeForSearch(entry.name)
        }

        // Synchronous snapshot: name matches + already-loaded content matches.
        publishSnapshot(entries: entries, tokens: tokens)

        guard let syncService else { return }

        let candidatesToLoad = entries.filter { entry in
            guard let normalized = normalizedNames[entry.id] else { return false }
            if RecipeSearchUtils.matchesName(normalized: normalized, tokens: tokens) {
                return false
            }
            return loadedSearchIndexes[entry.id] == nil
        }.prefix(100)

        guard !candidatesToLoad.isEmpty else { return }

        loadTask = Task { [weak self] in
            guard let self else { return }

            var newlyLoaded: [String: RecipeSearchIndex] = [:]
            for entry in candidatesToLoad {
                if Task.isCancelled { return }
                guard let index = await syncService.peekSearchIndex(recipeId: entry.id) else {
                    continue
                }
                newlyLoaded[entry.id] = index
            }

            guard !Task.isCancelled, !newlyLoaded.isEmpty else { return }

            await MainActor.run {
                self.loadedSearchIndexes.merge(newlyLoaded) { _, new in new }
                self.publishSnapshot(entries: entries, tokens: tokens)
            }
        }
    }

    /// Builds and publishes (single `objectWillChange`) the filtered snapshot
    /// and per-id highlights using the current caches.
    private func publishSnapshot(entries: [CollectionEntry], tokens: [String]) {
        var snapshot: [CollectionEntry] = []
        snapshot.reserveCapacity(entries.count)

        var newHighlights: [String: RecipeRowHighlight] = [:]
        newHighlights.reserveCapacity(entries.count)

        for entry in entries {
            guard let normalized = normalizedNames[entry.id] else { continue }
            let nameMatches = RecipeSearchUtils.matchesName(normalized: normalized, tokens: tokens)

            var snippetString: String? = nil
            if nameMatches {
                snapshot.append(entry)
            } else if let index = loadedSearchIndexes[entry.id],
                      RecipeSearchUtils.matchesRecipeContent(index, tokens: tokens) {
                snapshot.append(entry)
                snippetString = RecipeSearchUtils.snippet(
                    for: index,
                    tokens: tokens,
                    matchesNameOnly: false
                )
            } else {
                continue
            }

            let title = RecipeSearchUtils.highlightedAttributedString(
                RecipeTitleEmoji.displayName(for: entry.name),
                tokens: tokens,
                font: AppTypography.bodyUIFont,
                foregroundColor: .label
            )
            let snippet: AttributedString? = snippetString.map {
                RecipeSearchUtils.highlightedAttributedString(
                    $0,
                    tokens: tokens,
                    font: AppTypography.footnoteUIFont,
                    foregroundColor: .secondaryLabel
                )
            }
            newHighlights[entry.id] = RecipeRowHighlight(title: title, snippet: snippet)
        }

        // Two property writes — SwiftUI coalesces them into one render pass.
        filteredSnapshot = snapshot
        highlights = newHighlights
    }
}
