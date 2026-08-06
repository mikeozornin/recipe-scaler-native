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
    /// Spec 059 — Universal Link `https://…/discover`.
    case openDiscover
    /// Spec 059 — Universal Link `https://…/discover/collection/{slug}`.
    case openDiscoverCollection(slug: String)
    /// Spec 059 — Universal Link `https://…/discover/recipe/{recipeId}` (curated).
    case openDiscoverRecipe(recipeId: String)
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
    ///
    /// Canonical definition lives in `RecipeScalerCore.AppGroup.pendingRecipeIdKey`
    /// so both the extension targets (which cannot link the app target) and
    /// the host reference the same symbol. Kept here as a re-export so the
    /// existing call sites (`AppShellCoordinator`, tests) keep compiling
    /// without churn.
    static let pendingRecipeIdKey = AppGroup.pendingRecipeIdKey

    /// Last URL consumed by `handle(_:)` plus the wall-clock time it was
    /// routed. Guards against double delivery of the same Universal Link via
    /// both `.onOpenURL` and `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`
    /// (spec 059): on some scene/lifecycle configurations iOS calls both
    /// callbacks for one tap. The double-fire happens within milliseconds;
    /// a genuine second tap by the user is seconds-to-minutes apart.
    ///
    /// The TTL window (`lastHandledURLDedupWindow`) keeps the dedup tight
    /// enough to suppress iOS's same-tap double-fire, but wide enough that a
    /// real user re-tap of the same link still routes. Without TTL, a static
    /// `URL?` slot permanently blocks the second delivery and the user has
    /// to kill the app to navigate again. Code review 2026-08-05, finding #1.
    private static var lastHandledURL: URL?
    private static var lastHandledAt: Date?

    /// Same-tap double-delivery window. iOS double-fires within ~10–100 ms;
    /// 2 s leaves comfortable headroom for slower devices / scene transitions
    /// without absorbing a genuine second tap (which is rarely < 2 s apart).
    static let lastHandledURLDedupWindow: TimeInterval = 2

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
    /// Double-delivery guard: if the same URL was routed within
    /// `lastHandledURLDedupWindow`, this is a no-op. After the window
    /// elapses, the same URL routes again (real user re-tap).
    ///
    /// Supported routes:
    /// - `recipe-scaler://recipe/{recipeId}` → `.openRecipe`
    /// - `recipe-scaler://home` → `.openHome`
    /// - `recipe-scaler://shopping` → `.openShoppingList`
    /// - `https://recipe-scaler.ru/` → `.openHome`
    /// - `https://recipe-scaler.ru/recipe/{id}` → `.openRecipe`
    /// - `https://recipe-scaler.ru/shopping` → `.openShoppingList`
    /// - `https://recipe-scaler.ru/discover` → `.openDiscover`
    /// - `https://recipe-scaler.ru/discover/collection/{slug}` → `.openDiscoverCollection`
    /// - `https://recipe-scaler.ru/discover/recipe/{id}` → `.openDiscoverRecipe`
    /// - `https://recipe-scaler.ru/public/@/{username}` → `.openPublicProfile`
    /// - `https://recipe-scaler.ru/public/@/{username}/{recipeId}` → `.openPublicRecipe`
    static func handle(_ url: URL) {
        if let last = lastHandledURL, last == url,
           let handledAt = lastHandledAt,
           Date().timeIntervalSince(handledAt) < lastHandledURLDedupWindow {
            return
        }
        if let link = parse(url) {
            lastHandledURL = url
            lastHandledAt = Date()
            shared.handle(link)
        }
    }

    /// Test-only reset of the double-delivery guard.
    static func _resetLastHandledURLForTesting() {
        lastHandledURL = nil
        lastHandledAt = nil
    }

    /// Test-only backdate of the last delivery timestamp, so tests that want
    /// to simulate a post-TTL re-tap don't have to sleep for real seconds.
    static func _backdateLastHandledForTesting(by seconds: TimeInterval) {
        lastHandledAt = Date().addingTimeInterval(-seconds)
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
            guard url.pathComponents.filter({ $0 != "/" }).isEmpty else { return nil }
            return .openHome
        case "shopping":
            // Bare `recipe-scaler://shopping` only — not `://shopping/{id}`
            // (public shopping-list shares stay on https web).
            guard url.pathComponents.filter({ $0 != "/" }).isEmpty else { return nil }
            return .openShoppingList
        default:
            return nil
        }
    }

    /// Spec 059 — claimed AASA paths only. Unknown https paths return nil
    /// so Safari keeps them.
    private static func parseUniversalLink(_ url: URL) -> DeepLink? {
        guard let host = url.host?.lowercased(),
              Config.universalLinkHosts.contains(host) else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }

        if parts.isEmpty {
            return .openHome
        }

        switch parts[0] {
        case "shopping":
            guard parts.count == 1 else { return nil }
            return .openShoppingList

        case "recipe":
            guard parts.count == 2,
                  let recipeId = UUID(uuidString: parts[1])?.uuidString.lowercased() else {
                return nil
            }
            return .openRecipe(recipeId: recipeId)

        case "discover":
            if parts.count == 1 {
                return .openDiscover
            }
            guard parts.count == 3 else { return nil }
            switch parts[1] {
            case "collection":
                let slug = parts[2].removingPercentEncoding ?? parts[2]
                guard !slug.isEmpty else { return nil }
                return .openDiscoverCollection(slug: slug)
            case "recipe":
                guard let recipeId = UUID(uuidString: parts[2])?.uuidString.lowercased() else {
                    return nil
                }
                return .openDiscoverRecipe(recipeId: recipeId)
            default:
                return nil
            }

        case "public":
            // ["/public", "@", "username", optional "uuid"]
            guard parts.count >= 3, parts[1] == "@" else { return nil }
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

        default:
            return nil
        }
    }

    /// Legacy + App Group: consume recipe id written by Share/Action extensions.
    /// Extensions write into the App Group suite (separate from `UserDefaults.standard`).
    /// Returns `nil` when nothing is pending.
    static func consumePendingRecipeId() -> String? {
        if let suite = AppGroup.userDefaults,
           let id = suite.string(forKey: pendingRecipeIdKey),
           !id.isEmpty {
            suite.removeObject(forKey: pendingRecipeIdKey)
            return id
        }
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
