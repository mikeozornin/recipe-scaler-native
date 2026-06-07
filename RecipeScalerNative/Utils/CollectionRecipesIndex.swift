import Foundation

/// In-memory derived index for the collections view.
/// Mirrors `recipe-scaler-web/recipe-scaler/src/utils/collection-recipes-index.ts`.
struct CollectionRecipesIndex: Sendable, Equatable {
    /// All non-deleted recipes, in display order (pinned → A–Z → id).
    let live: [CollectionEntry]
    /// Live recipes whose `folderIds` is empty/absent.
    let uncategorized: [CollectionEntry]
    /// Recipe count per folder id (a recipe counted once per folder).
    let countByFolder: [String: Int]
    /// Recipes grouped per folder id; each list sorted for display.
    let folderRecipesById: [String: [CollectionEntry]]
}

enum CollectionRecipesIndexBuilder {
    /// Build the derived index from collection entries.
    /// Pass the full list (deleted included); the builder filters `deleted`.
    static func build(from recipes: [CollectionEntry]) -> CollectionRecipesIndex {
        var live: [CollectionEntry] = []
        var uncategorized: [CollectionEntry] = []
        var countByFolder: [String: Int] = [:]
        var folderRecipesById: [String: [CollectionEntry]] = [:]

        for recipe in recipes {
            if recipe.deleted { continue }
            live.append(recipe)

            let folderIds = recipe.folderIds
            if folderIds.isEmpty {
                uncategorized.append(recipe)
            }

            for folderId in folderIds {
                countByFolder[folderId, default: 0] += 1
                folderRecipesById[folderId, default: []].append(recipe)
            }
        }

        let sortedUncategorized = sortForDisplay(uncategorized)
        let sortedByFolder = folderRecipesById.mapValues(sortForDisplay)

        return CollectionRecipesIndex(
            live: sortForDisplay(live),
            uncategorized: sortedUncategorized,
            countByFolder: countByFolder,
            folderRecipesById: sortedByFolder
        )
    }

    /// Pinned first, then A–Z (case-insensitive, ignoring leading emoji), then id.
    /// Matches web `sortRecipesForListDisplay`.
    private static func sortForDisplay(_ entries: [CollectionEntry]) -> [CollectionEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            let nameOrder = RecipeTitleEmoji.compareNames(lhs.name, rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }
}
