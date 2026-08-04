//
//  DeepLinkRouter.swift
//  RecipeScalerNative
//
// Central deep-link dispatcher for Spotlight taps, URL scheme links,
// and Universal Links (spec 059).
//
// `AppShellCoordinator` (via `AppShellView`) observes `pending` and consumes the link once.
//

import Foundation
import RecipeScalerCore

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
    /// Spec 059 — Universal Link `https://…/public/@/{username}`.
    case openPublicProfile(username: String)
    /// Spec 059 — Universal Link `https://…/public/@/{username}/{recipeId}`.
    case openPublicRecipe(recipeId: String, username: String)
}

// MARK: - DeepLinkRouter

/// Central deep-link dispatcher for Spotlight taps, URL scheme links,
/// and Universal Links (spec 059).
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

    /// Last URL consumed by `handle(_:)`. Guards against double delivery of
    /// the same Universal Link via both `.onOpenURL` and
    /// `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` (spec 059):
    /// on some scene/lifecycle configurations iOS calls both callbacks for
    /// one tap. Without this guard, the second call would re-trigger
    /// navigation even after the coordinator cleared `pending`.
    /// Spec 059 architecture review, finding #2.
    private static var lastHandledURL: URL?

    var pending: DeepLink?

    init() {}

    func handle(_ link: DeepLink) {
        pending = link
    }

    func clear() {
        pending = nil
    }

    // MARK: - URL scheme + Universal Links

    /// Parse an inbound URL and queue it as a deep link.
    /// Called from `.onOpenURL` and Universal Link user activities.
    ///
    /// Double-delivery guard: if the same URL was already routed (see
    /// `lastHandledURL`), this is a no-op.
    ///
    /// Supported routes:
    /// - `recipe-scaler://recipe/{recipeId}` → `.openRecipe`
    /// - `recipe-scaler://home` → `.openHome`
    /// - `recipe-scaler://shopping` → `.openShoppingList`
    /// - `https://recipe-scaler.ru/public/@/{username}` → `.openPublicProfile`
    /// - `https://recipe-scaler.ru/public/@/{username}/{recipeId}` → `.openPublicRecipe`
    static func handle(_ url: URL) {
        if url == lastHandledURL { return }
        if let link = parse(url) {
            lastHandledURL = url
            shared.handle(link)
        }
    }

    /// Test-only reset of the double-delivery guard.
    static func _resetLastHandledURLForTesting() {
        lastHandledURL = nil
    }

    /// Pure parse for tests and callers that want the link without mutating state.
    static func parse(_ url: URL) -> DeepLink? {
        let scheme = url.scheme?.lowercased()
        if scheme == "recipe-scaler" {
            return parseCustomScheme(url)
        }
        if scheme == "https" || scheme == "http" {
            return parseUniversalLink(url)
        }
        return nil
    }

    private static func parseCustomScheme(_ url: URL) -> DeepLink? {
        switch url.host {
        case "recipe":
            guard let id = url.pathComponents.dropFirst().first,
                  !id.isEmpty,
                  let recipeId = UUID(uuidString: id)?.uuidString.lowercased() else { return nil }
            return .openRecipe(recipeId: recipeId)
        case "home":
            return .openHome
        case "shopping":
            return .openShoppingList
        default:
            return nil
        }
    }

    /// Spec 059 — only `/public/@/{username}` and `/public/@/{username}/{uuid}`.
    private static func parseUniversalLink(_ url: URL) -> DeepLink? {
        guard let host = url.host?.lowercased(),
              Config.universalLinkHosts.contains(host) else { return nil }

        // pathComponents: ["/", "public", "@", "username", optional "uuid"]
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3,
              parts[0] == "public",
              parts[1] == "@" else { return nil }

        let username = parts[2].removingPercentEncoding ?? parts[2]
        guard !username.isEmpty else { return nil }

        if parts.count == 3 {
            return .openPublicProfile(username: username)
        }

        guard parts.count == 4,
              let recipeId = UUID(uuidString: parts[3])?.uuidString.lowercased() else {
            return nil
        }
        return .openPublicRecipe(recipeId: recipeId, username: username)
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
