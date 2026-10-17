import Foundation

/// A user collection (folder / tag) entry from the collection Y.Doc.
///
/// Mirrors `Folder` from `recipe-scaler-web/shared/utils/folders-yjs.ts`.
/// Stored in the top-level `folders` `Y.Array<Y.Map>`. Soft-deleted entries
/// (`deleted == true`) are tombstones and must be preserved, not GC'd.
struct RecipeFolder: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let color: String
    let createdAt: String
    let updatedAt: String
    let deleted: Bool

    /// Sort active folders the way the web does: by display name
    /// (case-insensitive, ignoring a leading emoji), tie-break by id.
    ///
    /// The name keys are computed once per folder, and an input that is already in order
    /// (`YjsSyncService.folders`, re-sorted by views) costs `n - 1` comparisons: the sort is
    /// stable, so it would return that input unchanged.
    static func sortedActive(_ folders: [RecipeFolder]) -> [RecipeFolder] {
        let active = folders.filter { !$0.deleted }
        guard active.count > 1 else { return active }
        let keyed = active.map { (key: RecipeTitleEmoji.NameSortKey($0.name), folder: $0) }
        func inIncreasingOrder(
            _ lhs: (key: RecipeTitleEmoji.NameSortKey, folder: RecipeFolder),
            _ rhs: (key: RecipeTitleEmoji.NameSortKey, folder: RecipeFolder)
        ) -> Bool {
            let nameOrder = RecipeTitleEmoji.compare(lhs.key, rhs.key)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.folder.id.localizedStandardCompare(rhs.folder.id) == .orderedAscending
        }
        let isSorted = zip(keyed, keyed.dropFirst()).allSatisfy { !inIncreasingOrder($1, $0) }
        if isSorted { return active }
        return keyed.sorted(by: inIncreasingOrder).map(\.folder)
    }
}

/// Constants shared by the native folders implementation
/// (mirrors `recipe-scaler-web/shared/utils/folders-yjs.ts`).
enum RecipeFolderConstants {
    /// Top-level `Y.Array` key holding folder `Y.Map` entries.
    static let foldersArrayKey = "folders"

    /// `Y.Array` key holding recipe index entries (008).
    static let recipesArrayKey = "recipes"

    /// Optional recipe entry key: `string[]` of folder ids.
    static let folderIdsKey = "folderIds"

    /// Default color for new folders — matches web `DEFAULT_FOLDER_COLOR`.
    static let defaultFolderColor = "oklch(0.65 0.25 270)"

    /// Stored in Yjs when the user leaves a collection name blank.
    /// Map to i18n at display time (see `FolderDisplayName`).
    static let untitledFolderNameSentinel = ""

    /// Accent color string for a user folder icon; `nil` for virtual collections (use label color).
    static func presentationStoredColor(folderId: String, folder: RecipeFolder?) -> String? {
        guard !CollectionVirtualFolders.isKnownVirtualFolderId(folderId) else { return nil }
        return folder?.color ?? defaultFolderColor
    }

    /// Outline when empty, filled when the folder has at least one recipe.
    static func folderIconName(recipeCount: Int) -> String {
        recipeCount == 0 ? "folder" : "folder.fill"
    }
}
