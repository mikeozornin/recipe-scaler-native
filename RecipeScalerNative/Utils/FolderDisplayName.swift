import Foundation

/// Maps a stored folder name to a user-facing display string.
/// Mirrors `recipe-scaler-web/recipe-scaler/src/utils/folder-display-name.ts`.
enum FolderDisplayName {
    /// User-facing collection name.
    /// Empty / whitespace / sentinel storage → `recipes.no-title`.
    static func displayName(forStoredName name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "recipes.no-title")
        }
        return trimmed
    }
}
