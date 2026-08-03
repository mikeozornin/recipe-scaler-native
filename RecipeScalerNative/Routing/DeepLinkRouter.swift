//
//  DeepLinkRouter.swift
//  RecipeScalerNative
//
// Central deep-link dispatcher for Spotlight taps, URL scheme links,
// and future sources (Universal Links, notifications).
//
// `AppShellCoordinator` (via `AppShellView`) observes `pending` and consumes the link once.
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
    /// Spec 057 — incoming `.recipe` file via AirDrop / Files / Mail.
    /// The URL points to a security-scoped Inbox file that the coordinator
    /// copies to `tmp` before importing through `NativeExportImportService`.
    case openRecipeFile(URL)
}

// MARK: - DeepLinkRouter

/// Central deep-link dispatcher for Spotlight taps, URL scheme links,
/// and future sources (Universal Links, notifications).
///
/// `AppShellCoordinator` (via `AppShellView`) observes `pending` and consumes the link once.
///
@MainActor
@Observable
final class DeepLinkRouter {
    /// Shim: returns `AppContainer.shared.deepLinkRouter` when the container is
    /// constructed, otherwise a stand-alone instance.
    static var shared: DeepLinkRouter {
        if let container = AppContainer.shared {
            return container.deepLinkRouter
        }
        return Standalone
    }

    private static let Standalone = DeepLinkRouter()

    /// UserDefaults key for `recipe-scaler://recipe/{id}` links persisted
    /// by Share/Action extensions.
    static let pendingRecipeIdKey = "routing.pendingRecipeId"

    var pending: DeepLink?

    init() {}

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
