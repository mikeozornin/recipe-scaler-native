import SwiftUI

/// «Новая коллекция», shared by the phone collections list and the iPad sidebar
/// (spec 081, T017): the name is trimmed, an empty one is never saved, one save at a time.
@MainActor
enum NewCollectionCommit {
    /// The name to save, or `nil` when there is nothing to save.
    static func name(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Starts saving `name` unless a save is already in flight. A failure is silent: the
    /// user can retry. `completion` runs after the save either way.
    static func start(
        _ name: String,
        isSaving: Binding<Bool>,
        syncService: YjsSyncService,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        guard !isSaving.wrappedValue else { return }
        isSaving.wrappedValue = true
        Task { @MainActor in
            do {
                _ = try await syncService.createFolder(name: name)
            } catch {
                // Silently fail — user can retry.
            }
            isSaving.wrappedValue = false
            completion()
        }
    }
}
