//
//  ShoppingListSnapshotStore.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Persists the shopping list snapshot to App Group UserDefaults so that
/// App Intents can resolve shopping items even when the main app isn't running.
enum ShoppingListSnapshotStore {
    private static let appGroupID = AppGroup.id
    private static let key = "appIntents.shoppingListSnapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ snapshot: ShoppingListSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> ShoppingListSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(ShoppingListSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
