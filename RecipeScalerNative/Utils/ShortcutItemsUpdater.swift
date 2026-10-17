import UIKit

/// Updates Home Screen Quick Actions (long-press shortcut menu) with pinned recipes.
enum ShortcutItemType {
    static let openRecipe = "com.recipe-scaler.openRecipe"
}

enum ShortcutItemsUpdater {
    /// Ids and titles of the items last handed to UIKit.
    @MainActor private static var lastPinned: [RecipeSnapshot]?

    /// Rebuild `UIApplication.shared.shortcutItems` from the first 4 pinned entries.
    /// Call after `collectionEntries` changes (sync start, pin/unpin, rename, etc.).
    @MainActor
    static func update(from entries: [CollectionEntry]) {
        let pinned = CollectionEntry.sorted(entries.filter { $0.isPinned }).prefix(4)
        let items = pinned.map { RecipeSnapshot(id: $0.id, name: $0.name) }
        guard items != lastPinned else { return }
        lastPinned = items

        UIApplication.shared.shortcutItems = pinned.map { entry in
            UIApplicationShortcutItem(
                type: ShortcutItemType.openRecipe,
                localizedTitle: entry.name,
                localizedSubtitle: nil,
                icon: .init(systemImageName: "book.fill"),
                userInfo: ["recipeId": entry.id as NSSecureCoding]
            )
        }
    }
}
