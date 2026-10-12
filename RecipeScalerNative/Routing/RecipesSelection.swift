import Foundation

/// Selection in the Recipes section, read from and written to
/// `AppShellCoordinator.recipesPath` (spec 081, plan.md Р4).
///
/// The iPhone pushes routes into the array exactly as before; the iPad columns read
/// the same array, so the open recipe, collection and edit mode survive a size class
/// change (FR-018). The iPhone path is never normalized by these functions — only
/// the iPad writes canonical paths.
struct RecipesSelection: Equatable {
    /// Last `.folder` of the path: a user collection id or a virtual folder
    /// (`CollectionVirtualFolders`). `nil` is «Все рецепты» in the flat list.
    var collectionId: String?
    /// Last `.recipe` of the path.
    var recipeId: String?
    /// `folderContext` of that `.recipe` route (iPhone back-navigation hint).
    var recipeFolderContext: String?
    var openInEditMode: Bool

    init(
        collectionId: String? = nil,
        recipeId: String? = nil,
        recipeFolderContext: String? = nil,
        openInEditMode: Bool = false
    ) {
        self.collectionId = collectionId
        self.recipeId = recipeId
        self.recipeFolderContext = recipeFolderContext
        self.openInEditMode = openInEditMode
    }

    // MARK: - Path ↔ selection

    /// The last `.folder` and the last `.recipe` of the path.
    static func selection(from path: [RecipesRoute]) -> RecipesSelection {
        var selection = RecipesSelection()
        for route in path {
            switch route {
            case .folder(let folderId):
                selection.collectionId = folderId
            case .recipe(let recipeId, let folderContext, let openInEditMode):
                selection.recipeId = recipeId
                selection.recipeFolderContext = folderContext
                selection.openInEditMode = openInEditMode
            }
        }
        return selection
    }

    /// Canonical path: `[.folder]` when a collection is selected, then `[.recipe]`.
    static func path(for selection: RecipesSelection) -> [RecipesRoute] {
        var path: [RecipesRoute] = []
        if let collectionId = selection.collectionId {
            path.append(.folder(collectionId))
        }
        if let recipeId = selection.recipeId {
            path.append(.recipe(
                recipeId: recipeId,
                folderContext: selection.recipeFolderContext,
                openInEditMode: selection.openInEditMode
            ))
        }
        return path
    }

    // MARK: - iPad selection changes

    /// Opens `recipeId` in the panel, keeping the collection selected in `path`.
    static func selectingRecipe(
        _ recipeId: String,
        in path: [RecipesRoute],
        folderContext: String? = nil,
        openInEditMode: Bool = false
    ) -> [RecipesRoute] {
        var selection = selection(from: path)
        selection.recipeId = recipeId
        selection.recipeFolderContext = folderContext
        selection.openInEditMode = openInEditMode
        return self.path(for: selection)
    }

    /// Selects a collection and opens its first recipe; an empty collection gives `[.folder(id)]`.
    static func selectingCollection(
        _ collectionId: String,
        firstRecipeId: String?,
        folderContext: String? = nil
    ) -> [RecipesRoute] {
        path(for: RecipesSelection(
            collectionId: collectionId,
            recipeId: firstRecipeId,
            recipeFolderContext: firstRecipeId == nil ? nil : folderContext
        ))
    }

    /// «Все рецепты» with the open recipe kept (prototype: the sidebar row «Рецепты» and
    /// the title menu); edit mode is dropped.
    static func selectingAllRecipes(in path: [RecipesRoute]) -> [RecipesRoute] {
        self.path(for: RecipesSelection(recipeId: selection(from: path).recipeId))
    }

    // MARK: - Remote deletions

    /// Repairs a selection after a sync removed what it points to (spec.md edge cases):
    /// - the selected collection is gone (or unknown) → «Все рецепты»;
    /// - the open recipe is gone → the next one of `previousRecipeIds` that still exists,
    ///   else the previous one, else the first of `recipeIds`; edit mode is dropped.
    ///
    /// `recipeIds` is the list as shown now (pinned first) for the repaired collection;
    /// `previousRecipeIds` is the list as shown before the change.
    static func resolvingDeletions(
        _ selection: RecipesSelection,
        userFolderIds: [String],
        recipeIds: [String],
        previousRecipeIds: [String]
    ) -> RecipesSelection {
        var resolved = selection
        if let collectionId = selection.collectionId,
           !RecipeFolderRoutes.isValidFolderId(collectionId, userFolderIds: userFolderIds) {
            resolved.collectionId = nil
            resolved.recipeFolderContext = nil
        }
        guard let recipeId = selection.recipeId, !recipeIds.contains(recipeId) else {
            return resolved
        }
        let existing = Set(recipeIds)
        let replacement: String?
        if let index = previousRecipeIds.firstIndex(of: recipeId) {
            replacement = previousRecipeIds[previousRecipeIds.index(after: index)...].first { existing.contains($0) }
                ?? previousRecipeIds[..<index].last { existing.contains($0) }
                ?? recipeIds.first
        } else {
            replacement = recipeIds.first
        }
        resolved.recipeId = replacement
        resolved.recipeFolderContext = replacement == nil ? nil : resolved.recipeFolderContext
        resolved.openInEditMode = false
        return resolved
    }

    // MARK: - iPad split (T028)

    /// The path the iPad split writes back, or `nil` when `path` stays as it is.
    ///
    /// - A path the shared phone code appended to (deep links, Spotlight, import:
    ///   `[.folder, .recipe, .recipe]`) becomes canonical; a recipe outside the selected
    ///   collection opens in «Все рецепты», so its row is highlighted.
    /// - The selected collection is gone → «Все рецепты».
    /// - The open recipe was deleted (it was in `previousLiveRecipeIds` and is not in
    ///   `liveRecipeIds`) → `resolvingDeletions` over the list as it was. A recipe that has
    ///   not reached the list yet (just created) or only left the collection stays open.
    /// - Nothing open → the first recipe of the list (pinned first).
    ///
    /// `listRecipeIds` gives a list as the column shows it: `nil` is «Все рецепты».
    static func splitRepairedPath(
        _ path: [RecipesRoute],
        userFolderIds: [String],
        liveRecipeIds: Set<String>,
        previousLiveRecipeIds: Set<String>,
        listRecipeIds: (_ collectionId: String?) -> [String],
        previousListRecipeIds: [String]
    ) -> [RecipesRoute]? {
        var selection = selection(from: path)
        let isCanonical = self.path(for: selection) == path
        if let collectionId = selection.collectionId {
            let isGone = !RecipeFolderRoutes.isValidFolderId(collectionId, userFolderIds: userFolderIds)
            let isOutside = !isCanonical
                && selection.recipeId.map { !listRecipeIds(collectionId).contains($0) } == true
            if isGone || isOutside {
                selection.collectionId = nil
                selection.recipeFolderContext = nil
            }
        }
        let list = listRecipeIds(selection.collectionId)
        if let recipeId = selection.recipeId {
            if !liveRecipeIds.contains(recipeId), previousLiveRecipeIds.contains(recipeId) {
                selection = resolvingDeletions(
                    selection,
                    userFolderIds: userFolderIds,
                    recipeIds: list,
                    previousRecipeIds: previousListRecipeIds
                )
            }
        } else if let first = list.first {
            selection.recipeId = first
            selection.recipeFolderContext = selection.collectionId
            selection.openInEditMode = false
        }
        let repaired = self.path(for: selection)
        return repaired == path ? nil : repaired
    }
}
