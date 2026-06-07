import Foundation

/// Recipe metadata entry from the collection Y.Doc.
/// Read from `Y.Array('recipes')` → `Y.Map` per entry.
struct CollectionEntry: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let color: String
    let imageUrl: String?
    let updatedAt: String
    let deleted: Bool
    let isPinned: Bool
    /// Ids of collections (folders) this recipe belongs to.
    /// Empty when the underlying Y.Map has no `folderIds` key
    /// (native 008 compat) or an empty array after normalization.
    let folderIds: [String]

    init(
        id: String,
        name: String,
        color: String,
        imageUrl: String?,
        updatedAt: String,
        deleted: Bool,
        isPinned: Bool,
        folderIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.imageUrl = imageUrl
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.isPinned = isPinned
        self.folderIds = folderIds
    }

    /// Sort entries: pinned first, then alphabetically by display name (emoji ignored), then id.
    static func sorted(_ entries: [CollectionEntry]) -> [CollectionEntry] {
        RecipeTitleEmoji.sortCollectionEntries(entries.filter { !$0.deleted })
    }
}
