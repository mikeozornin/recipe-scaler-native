//
//  ShoppingIntentActionQueue.swift
//  RecipeScalerNative
//

import Foundation

enum ShoppingIntentAction: Codable, Sendable {
    case addItem(label: String)
}

/// App Group queue for shopping list actions enqueued by App Intents.
/// Drained by `ShoppingIntentDrainer` when the app enters foreground with an active sync session.
enum ShoppingIntentActionQueue {
    private static let appGroupID = "group.ru.recipescaler.RecipeScalerNative"
    private static let key = "appIntents.pendingShoppingActions"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func enqueue(_ action: ShoppingIntentAction) {
        var pending = load()
        pending.append(action)
        guard let data = try? JSONEncoder().encode(pending) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> [ShoppingIntentAction] {
        guard let data = defaults?.data(forKey: key),
              let actions = try? JSONDecoder().decode([ShoppingIntentAction].self, from: data)
        else { return [] }
        return actions
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}

@MainActor
enum ShoppingIntentDrainer {
    static func drainIfNeeded(syncService: YjsSyncService) {
        guard syncService.currentUserId != nil else { return }
        let pending = ShoppingIntentActionQueue.load()
        guard !pending.isEmpty else { return }
        ShoppingIntentActionQueue.clear()
        Task {
            for action in pending {
                switch action {
                case .addItem(let label):
                    try? await syncService.addManualShoppingItem(label: label)
                }
            }
        }
    }
}
