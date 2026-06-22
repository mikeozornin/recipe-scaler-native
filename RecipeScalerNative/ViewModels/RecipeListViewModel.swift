import Foundation
import SwiftUI

/// Owns derived render state for `RecipeListView`: pinned and unpinned row
/// snapshots plus the sorted/filtered `[CollectionEntry]` feed.
///
/// The view remains a thin consumer — it triggers `refresh()` from SwiftUI
/// `onChange`/`.task` hooks and reads `pinnedRows` / `unpinnedRows`. Sort and
/// split happen once per refresh, not on every render (the previous inline
/// `rowItemsCacheKey` rebuilt an O(n) `[String]` and string-compared it each
/// frame). Action methods (`createRecipe`, `setRecipePinned`, …) stay on
/// `YjsSyncService` — this type owns state for display only.
@MainActor
@Observable
final class RecipeListViewModel {
    /// Rows in the pinned section, precomputed by the last `refresh()`.
    private(set) var pinnedRows: [RecipeRowData] = []

    /// Rows in the unpinned section, precomputed by the last `refresh()`.
    private(set) var unpinnedRows: [RecipeRowData] = []

    /// Snapshot the view should render: pre-built filtered list when a search
    /// is active, the full sorted list otherwise. Computed on demand from the
    /// bound services — no caching, because the inputs are already cached.
    var filteredEntries: [CollectionEntry] {
        guard let syncService else { return [] }
        if let searchStore, searchStore.isActive {
            return searchStore.filteredSnapshot
        }
        return RecipeTitleEmoji.sortCollectionEntries(syncService.collectionEntries)
    }

    private weak var syncService: YjsSyncService?
    private weak var searchStore: RecipeListSearchStore?

    init(syncService: YjsSyncService? = nil) {
        self.syncService = syncService
    }

    /// Wire the view-model to its source services. Called from the view's
    /// `.onAppear` / `.task`. Both references are weak to avoid a retain cycle:
    /// the view owns the VM via `@State`, and the services live in the SwiftUI
    /// environment outliving the view.
    func bind(syncService: YjsSyncService, searchStore: RecipeListSearchStore) {
        self.syncService = syncService
        self.searchStore = searchStore
    }

    /// Rebuild `pinnedRows` / `unpinnedRows` from the current `filteredEntries`.
    /// Idempotent — safe to call from multiple SwiftUI hooks. No-ops when the
    /// services are not bound yet (early `onAppear` before `bind`).
    func refresh() {
        let entries = filteredEntries
        var pinned: [RecipeRowData] = []
        var unpinned: [RecipeRowData] = []
        pinned.reserveCapacity(entries.count)
        unpinned.reserveCapacity(entries.count)
        for entry in entries {
            if entry.isPinned {
                pinned.append(RecipeRowData(entry: entry))
            } else {
                unpinned.append(RecipeRowData(entry: entry))
            }
        }
        pinnedRows = pinned
        unpinnedRows = unpinned
    }
}
