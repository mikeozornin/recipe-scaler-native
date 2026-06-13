//
//  RecipeSnapshotStore.swift
//  RecipeScalerNative
//

import Foundation

struct RecipeSnapshot: Codable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// Persists a lightweight list of recipes to App Group UserDefaults so that
/// App Intents can resolve recipe entities even when the main app isn't running.
enum RecipeSnapshotStore {
    static let appGroupID = "group.ru.recipescaler.RecipeScalerNative"
    private static let key = "appIntents.recipeSnapshots"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ entries: [CollectionEntry]) {
        let snapshots = entries
            .filter { !$0.deleted }
            .map { RecipeSnapshot(id: $0.id, name: $0.name) }
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> [RecipeSnapshot] {
        guard let data = defaults?.data(forKey: key),
              let snapshots = try? JSONDecoder().decode([RecipeSnapshot].self, from: data)
        else { return [] }
        return snapshots
    }
}
