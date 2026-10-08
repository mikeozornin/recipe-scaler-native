import Foundation

/// Native navigation helpers for the collections folder routes.
/// Mirrors `recipe-scaler-web/recipe-scaler/src/utils/recipe-folder-routes.ts`.
///
/// The web uses URL paths (`/folder/:id`, `/folder/:id/recipe/:rid`,
/// `/recipe/:id`). On native we don't pass strings between screens —
/// the helpers below expose the route *decisions* the UI needs
/// (folder context for back, recipe link target).
enum RecipeFolderRoutes {
    /// View modes persisted locally (web: `localStorage` key
    /// `recipe-list-view-mode`; native: `UserDefaults`).
    enum ViewMode: String {
        case flat
        case collections
    }

    /// `UserDefaults` key for the view mode the user picked explicitly.
    /// Absent until the user touches the switcher — see `effectiveViewMode`.
    static let viewModeStorageKey = "recipe-list-view-mode"

    /// Mode to show: the user's explicit pick wins; otherwise collections only
    /// once the user has a collection of their own. With none, the grid holds
    /// just «All recipes» and «Uncategorized» — an extra tap to reach recipes.
    static func effectiveViewMode(storedRaw: String?, hasUserFolders: Bool) -> ViewMode {
        if let storedRaw, let stored = ViewMode(rawValue: storedRaw) {
            return stored
        }
        return hasUserFolders ? .collections : .flat
    }

    /// How the collections root is displayed: plain list or folder grid.
    enum CollectionsRootLayout: String, CaseIterable, Identifiable, Hashable {
        case list
        case folders

        var id: String { rawValue }
    }

    /// `UserDefaults` key for the saved collections root layout (default `folders`).
    static let collectionsRootLayoutStorageKey = "recipe-collections-root-layout"

    /// Layout used when `recipe-collections-root-layout` is absent or invalid.
    static let defaultCollectionsRootLayout: CollectionsRootLayout = .folders

    /// Whether opening a recipe from the current folder should use the nested
    /// folder route. Flat mode and recipes with no folder membership (except
    /// the virtual «uncategorized») keep the root `/recipe/:id` semantics.
    ///
    /// Mirrors `shouldUseFolderRecipePath`.
    static func shouldUseFolderRecipePath(
        activeFolderId: String?,
        viewMode: ViewMode,
        recipeFolderIds: [String]?
    ) -> Bool {
        guard let activeFolderId, viewMode == .collections else {
            return false
        }

        if activeFolderId == CollectionVirtualFolders.uncategorizedFolderId {
            return true
        }

        if activeFolderId == CollectionVirtualFolders.allRecipesFolderId {
            return (recipeFolderIds?.isEmpty == false)
        }

        guard let ids = recipeFolderIds, !ids.isEmpty else {
            return false
        }

        return ids.contains(activeFolderId)
    }

    /// Whether the folder id refers to an existing folder (virtual or user).
    /// Used to validate deep-link targets.
    static func isValidFolderId(_ folderId: String, userFolderIds: [String]) -> Bool {
        if CollectionVirtualFolders.isKnownVirtualFolderId(folderId) {
            return true
        }
        return userFolderIds.contains(folderId)
    }
}
