/// Result shared by the manual import sheet and the platform-neutral file
/// import coordinator.
struct ImportRecipesResult {
    let recipeIds: [String]
    let importedCount: Int

    init(recipeIds: [String], importedCount: Int? = nil) {
        self.recipeIds = recipeIds
        self.importedCount = importedCount ?? recipeIds.count
    }

    var primaryRecipeId: String? {
        recipeIds.count == 1 ? recipeIds.first : nil
    }
}
