import Foundation

/// Recipe metadata entry from the collection Y.Doc.
/// Read from `Y.Array('recipes')` → `Y.Map` per entry.
struct CollectionEntry: Identifiable, Sendable {
    let id: String
    let name: String
    let color: String
    let imageUrl: String?
    let updatedAt: String
    let deleted: Bool
    let isPinned: Bool

    /// Sort entries: pinned first, then by updatedAt descending.
    static func sorted(_ entries: [CollectionEntry]) -> [CollectionEntry] {
        entries
            .filter { !$0.deleted }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }
}
