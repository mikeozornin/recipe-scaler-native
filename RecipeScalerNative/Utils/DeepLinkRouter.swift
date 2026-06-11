//
//  DeepLinkRouter.swift
//  RecipeScalerNative
//
//  Central deep-link dispatcher for Spotlight taps, URL scheme links,
//  and future sources (Universal Links, notifications).
//
//  The active `AppShellView` observes `pending` and consumes the link once.
//

import Combine
import Foundation

// MARK: - DeepLink

enum DeepLink: Equatable, Sendable {
    case openRecipe(recipeId: String)
    case addToShopping(recipeId: String)
}

// MARK: - DeepLinkRouter

/// Singleton that holds the most recent unprocessed deep link.
/// Callers write via `handle(_:)`, the scene reads via `$pending`
/// and clears via `clear()` after consumption.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    /// UserDefaults key for `recipe-scaler://recipe/{id}` links persisted
    /// by Share/Action extensions.
    static let pendingRecipeIdKey = "routing.pendingRecipeId"

    @Published var pending: DeepLink?

    private init() {}

    func handle(_ link: DeepLink) {
        pending = link
    }

    func clear() {
        pending = nil
    }

    // MARK: - URL scheme

    /// Parse an inbound `recipe-scaler://recipe/{recipeId}` URL and queue
    /// it as `.openRecipe` deep link. Called from `.onOpenURL`.
    static func handle(_ url: URL) {
        guard url.scheme == "recipe-scaler",
              url.host == "recipe",
              let id = url.pathComponents.dropFirst().first,
              !id.isEmpty,
              let recipeId = UUID(uuidString: id)?.uuidString else { return }
        shared.handle(.openRecipe(recipeId: recipeId))
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
