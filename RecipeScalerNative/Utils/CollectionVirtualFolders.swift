import Foundation

/// Virtual folder ids that exist only in UI — never stored in Yjs.
/// Mirrors `recipe-scaler-web/shared/utils/collection-virtual-folders.ts`.
enum CollectionVirtualFolders {
    /// Every non-deleted recipe; mirrors flat-mode content.
    static let allRecipesFolderId = "all"

    /// Recipes with no `folderIds` (empty / absent).
    static let uncategorizedFolderId = "uncategorized"

    /// True when the id is a built-in virtual collection folder.
    static func isKnownVirtualFolderId(_ folderId: String) -> Bool {
        folderId == allRecipesFolderId || folderId == uncategorizedFolderId
    }
}
