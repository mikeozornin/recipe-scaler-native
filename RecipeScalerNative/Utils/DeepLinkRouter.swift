//
//  DeepLinkRouter.swift
//  RecipeScalerNative
//
// Central deep-link dispatcher for Spotlight taps, URL scheme links,
// and future sources (Universal Links, notifications).
//
// The active `AppShellView` observes `pending` and consumes the link once.
//

import Foundation

// MARK: - DeepLink

enum DeepLink: Equatable, Sendable {
    case openRecipe(recipeId: String)
    case addToShopping(recipeId: String)
    case openShoppingList
    /// Opens the app on the default tab (`.recipes`). Used by `TimerWidget`
    /// taps on the Home Screen — there is no dedicated timers tab in the app.
    case openHome
}

// MARK: - DeepLinkRouter

/// Singleton that holds the most recent unprocessed deep link.
/// Callers write via `handle(_:)`, the scene reads via `pending`
/// and clears via `clear()` after consumption.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// UserDefaults key for `recipe-scaler://recipe/{id}` links persisted
    /// by Share/Action extensions.
    static let pendingRecipeIdKey = "routing.pendingRecipeId"

    var pending: DeepLink?

    private init() {}

    func handle(_ link: DeepLink) {
        pending = link
    }

    func clear() {
        pending = nil
    }

    // MARK: - URL scheme

    /// Parse an inbound `recipe-scaler://` URL and queue it as a deep link.
    /// Called from `.onOpenURL`.
    ///
    /// Supported routes:
    /// - `recipe-scaler://recipe/{recipeId}` → `.openRecipe`
    /// - `recipe-scaler://home` → `.openHome`
    /// - `recipe-scaler://shopping` → `.openShoppingList`
    static func handle(_ url: URL) {
        guard url.scheme == "recipe-scaler" else { return }
        switch url.host {
        case "recipe":
            guard let id = url.pathComponents.dropFirst().first,
                  !id.isEmpty,
                  let recipeId = UUID(uuidString: id)?.uuidString.lowercased() else { return }
            shared.handle(.openRecipe(recipeId: recipeId))
        case "home":
            shared.handle(.openHome)
        case "shopping":
            shared.handle(.openShoppingList)
        default:
            return
        }
    }

    /// Legacy: consume recipe id written by extensions into UserDefaults.
    /// Returns `nil` when nothing is pending.
    static func consumePendingRecipeId() -> String? {
        let id = UserDefaults.standard.string(forKey: pendingRecipeIdKey)
        if id != nil {
            UserDefaults.standard.removeObject(forKey: pendingRecipeIdKey)
        }
        return id
    }
}

// MARK: - Notification (legacy URL scheme support)

extension Notification.Name {
    /// Posted after a `recipe-scaler://` URL is processed.
    static let openRecipeRequested = Notification.Name("openRecipeRequested")
}
