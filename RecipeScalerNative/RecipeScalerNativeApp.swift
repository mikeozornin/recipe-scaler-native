//
//  RecipeScalerNativeApp.swift
//  RecipeScalerNative
//
//

import CoreSpotlight
import SwiftUI
import SwiftData
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await PushRegistrationService.shared.register(apnsToken: token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLog.error(.push, "apns_register_failed", data: ["error": error.localizedDescription])
    }

    /// Spec 030 B4 — silent `content-available` wake refreshes the TimerWidget snapshot.
    /// Alert pushes (023 timer completed) keep system / UNUserNotificationCenter presentation;
    /// this path never suppresses alerts — it only optionally refreshes App Group state.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard WidgetSilentPushHandler.shouldRefreshWidget(userInfo: userInfo) else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let updated = await WidgetSilentPushHandler.refreshSnapshotFromServer()
            completionHandler(updated ? .newData : .failed)
        }
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Spec 039 — activate WCSession so AuthService can publish userId to
        // a paired Apple Watch. No-op when WCSession is unsupported (iPad,
        // Simulator without watch).
        WatchCredentialsBridge.shared.activate()
        return true
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

    /// Single source of truth for all app-level services (review #27).
    /// Built once on cold start; provided to SwiftUI via `@Environment(AppContainer.self)`
    /// through `appEnvironment(_:)`. AppIntents and other non-SwiftUI callers access
    /// it via `AppContainer.shared`.
    @State private var container: AppContainer

    init() {
        // Install bundle swizzle + apply stored language preference before any
        // SwiftUI view body evaluates `String(localized:)` / `LocalizedStringKey`.
        AppLanguagePreference.bootstrap()
        // Force CoreText registration of bundled Martian OTF faces now, so the
        // first .environment(\.font, AppTypography.body) lookup resolves them.
        // This is the single source of truth for the main app target — the
        // Info.plist of RecipeScalerNative intentionally has no UIAppFonts key,
        // otherwise UIKit re-registers the same files lazily and CoreText logs
        // "GSFont: file already registered" warnings. Widget extensions still
        // use UIAppFonts because they have no app delegate to call this from.
        AppFonts.registerBundledFontsIfNeeded()
        TimerManager.registerBackgroundTasksIfNeeded()
        AppChromeAppearance.configure()

        // Construct the dependency graph. SwiftData ModelContainer is created
        // synchronously first (separate from AppContainer; owned by WindowGroup).
        let modelContext = ModelContext(Self.sharedModelContainer)
        do {
            container = try AppContainer(modelContext: modelContext)
        } catch {
            // The only failure path is YrsDatabase corruption; AppContainer
            // already tries an in-memory fallback internally before rethrowing,
            // so by this point recovery is impossible.
            fatalError("Cannot initialize AppContainer: \(error)")
        }
    }

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RecipeTimer.self
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
            AppLog.error(.database, "SwiftData store corrupted, recreating: \(error)")

            // Delete corrupted store files (including WAL journal and shared memory)
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            let storeFiles = [
                "default.store",
                "default.store-wal",
                "default.store-shm"
            ]
            for fileName in storeFiles {
                let url = appSupport.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: url)
            }

            // Retry with fresh store
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
            } catch {
                fatalError("Could not create ModelContainer after deleting corrupted store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appEnvironment(container)
                .onOpenURL { url in
                    // Spec 057: file:// URLs (AirDrop, Files, Mail attachments)
                    // go through a dedicated deep-link path that imports the
                    // file directly without presenting ImportRecipeSheet.
                    if url.isFileURL {
                        DeepLinkRouter.shared.handle(.openRecipeFile(url))
                        return
                    }
                    DeepLinkRouter.handle(url)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightActivity(activity)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { [container] activity in
                    guard let url = activity.webpageURL else { return }
                    if let link = DeepLinkRouter.parse(url) {
                        container.deepLinkRouter.handle(link)
                    }
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

