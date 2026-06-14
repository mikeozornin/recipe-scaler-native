//
//  RecipeScalerNativeApp.swift
//  RecipeScalerNative
//
//

import CoreSpotlight
import SwiftUI
import SwiftData
import UIKit
#if DEBUG
import Agentation
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await PushRegistrationService.shared.register(apnsToken: token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }

    // MARK: - Home Screen Quick Actions

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard shortcutItem.type == ShortcutItemType.openRecipe,
              let recipeId = shortcutItem.userInfo?["recipeId"] as? String else {
            completionHandler(false)
            return
        }
        DeepLinkRouter.shared.handle(.openRecipe(recipeId: recipeId))
        completionHandler(true)
    }
}

@main
struct RecipeScalerNativeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Install bundle swizzle + apply stored language preference before any
        // SwiftUI view body evaluates `String(localized:)` / `LocalizedStringKey`.
        AppLanguagePreference.bootstrap()
        TimerManager.registerBackgroundTasksIfNeeded()
        AppChromeAppearance.configure()
        #if DEBUG
        Agentation.shared.toolbarHorizontalAlignment = .leading
        Agentation.shared.install()
        #endif
    }

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            Ingredient.self,
            RecipeTimer.self,
            ApiCacheEntry.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    DeepLinkRouter.handle(url)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightActivity(activity)
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }

    /// Decode Spotlight tap: card itself → `.openRecipe`, action button → `.addToShopping`.
    private func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard let recipeId = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              !recipeId.isEmpty else {
            return
        }
        if let actionId = activity.userInfo?[CSActionIdentifier] as? String,
           actionId == SpotlightIndexer.actionAddToShopping {
            DeepLinkRouter.shared.handle(.addToShopping(recipeId: recipeId))
        } else {
            DeepLinkRouter.shared.handle(.openRecipe(recipeId: recipeId))
        }
    }

}

