import Foundation

/// Navigation routes for the Recipes tab.
///
/// Replaces flat `String` recipe ids in `NavigationPath` with typed routes
/// that carry optional folder context for back-navigation parity with the web.
enum RecipesRoute: Hashable {
    /// Drill into a collection folder (virtual or user).
    /// `folderId` is a UUID for user folders, or one of
    /// `CollectionVirtualFolders.allRecipesFolderId` / `.uncategorizedFolderId`.
    case folder(String)

    /// Open a recipe detail. `folderContext` is non-nil when the recipe was
    /// opened from a folder drill-in (used for back-navigation target).
    /// `openInEditMode` mirrors web `location.state.isNewRecipe` after create/import.
    case recipe(recipeId: String, folderContext: String?, openInEditMode: Bool = false)
}
