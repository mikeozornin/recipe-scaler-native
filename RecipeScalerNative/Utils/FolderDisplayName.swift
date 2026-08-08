import Foundation

struct FolderDisplayNamePresentation: Equatable, Sendable {
    let leadingEmoji: String?
    let displayName: String
}

/// Maps a stored folder name to a user-facing display string.
/// Mirrors `recipe-scaler-web/recipe-scaler/src/utils/folder-display-name.ts`.
enum FolderDisplayName {
    /// Separates a leading emoji marker from the localized collection label.
    /// The stored name is never modified by this presentation helper.
    static func presentation(forStoredName name: String) -> FolderDisplayNamePresentation {
        let rawDisplayName = RecipeTitleEmoji.displayName(for: name)
        let trimmedStoredName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = rawDisplayName.isEmpty || trimmedStoredName == RecipeFolderConstants.untitledFolderNameSentinel
            ? String(localized: "recipes.no-title")
            : rawDisplayName

        return FolderDisplayNamePresentation(
            leadingEmoji: RecipeTitleEmoji.leadingEmoji(in: name),
            displayName: displayName
        )
    }

    /// User-facing collection name.
    /// Empty / whitespace / sentinel storage → `recipes.no-title`.
    static func displayName(forStoredName name: String) -> String {
        presentation(forStoredName: name).displayName
    }
}
