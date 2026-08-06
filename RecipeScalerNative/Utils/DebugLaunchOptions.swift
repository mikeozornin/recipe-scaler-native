//
//  DebugLaunchOptions.swift
//  RecipeScalerNative
//

import Foundation
import UserNotifications

#if DEBUG
enum DebugLaunchOptions {
    /// Skip splash (verify scripts, deep links).
    static var shouldSkipSplash: Bool {
        if ProcessInfo.processInfo.arguments.contains("ui-testing") { return true }
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-SkipSplash=1" || arg == "-SkipSplash" { return true }
        }
        return openRecipeId != nil
            || openRecipeName != nil
            || openTab != nil
            || openDiscoverProfileUsername != nil
            || openDiscoverCollectionSlug != nil
            || startDescriptionEdit
            || startInEditMode
            || showRecipeShare
            || showAssistant
            || openShoppingShare
            || shoppingShareAutoCopyText
            || simulateErrorAlert
            || screenshotCapture
            || screenshotTimerSeconds != nil
            || screenshotShoppingSeed != nil
    }

    /// `-ScreenshotCapture=1` — store screenshot mode (hide system banner chrome).
    static var screenshotCapture: Bool {
        boolFlag("ScreenshotCapture")
    }

    /// `-OpenShoppingShare=1` — opens shopping share sheet (verify scripts).
    static var openShoppingShare: Bool {
        boolFlag("OpenShoppingShare")
    }

    /// `-ShoppingShareAutoCopyText=1` — copies list as text from share sheet (verify scripts).
    static var shoppingShareAutoCopyText: Bool {
        boolFlag("ShoppingShareAutoCopyText")
    }

    /// `-ShowAssistant=1` — opens assistant sheet on launch (verify 015).
    static var showAssistant: Bool {
        boolFlag("ShowAssistant")
    }

    /// `-ScreenshotAssistantFixture=1` — injects about-media troubleshooting chat (no live LLM).
    static var screenshotAssistantFixture: Bool {
        boolFlag("ScreenshotAssistantFixture")
    }

    /// `-MobileTimerPanelExpanded=1` — timer panel starts expanded (verify scripts).
    static var mobileTimerPanelExpanded: Bool {
        boolFlag("MobileTimerPanelExpanded")
    }

    /// `-ScrollToNewIngredient=1` — scroll edit grid to the «+» row (verify scripts).
    static var scrollToNewIngredient: Bool {
        boolFlag("ScrollToNewIngredient")
    }

    /// `-StartInEditMode=1` — recipe detail opens in edit mode.
    static var startInEditMode: Bool {
        if boolFlag("StartInEditMode") { return true }
        return startDescriptionEdit
    }

    /// `-ShowRecipeShare=1` — opens system share sheet on recipe detail (verify 012).
    static var showRecipeShare: Bool {
        boolFlag("ShowRecipeShare")
    }

    /// `xcrun simctl launch … -OpenRecipeId=<uuid>` — opens recipe detail after collection loads.
    static var openRecipeId: String? {
        stringValue("OpenRecipeId")
    }

    /// `-OpenRecipeName=Strudel` — opens first non-deleted collection recipe matching name.
    static var openRecipeName: String? {
        stringValue("OpenRecipeName")
    }

    /// `-OpenDiscoverProfile=<username>` — Discover → public profile.
    static var openDiscoverProfileUsername: String? {
        stringValue("OpenDiscoverProfile")
    }

    /// `-OpenDiscoverCollection=<slug>` — Discover → curated collection.
    static var openDiscoverCollectionSlug: String? {
        stringValue("OpenDiscoverCollection")
    }

    /// `-ScreenshotScaleFactor=2` — force recipe detail scale after load.
    static var screenshotScaleFactor: Double? {
        guard let raw = stringValue("ScreenshotScaleFactor"),
              let value = Double(raw),
              value.isFinite,
              value > 0 else { return nil }
        return value
    }

    /// `-ScreenshotScreenAwake=1` — force cooking wake-lock banner on.
    static var screenshotScreenAwake: Bool {
        boolFlag("ScreenshotScreenAwake")
    }

    /// `-ScreenshotTimerSeconds=2700` — start a countdown timer on launch.
    static var screenshotTimerSeconds: TimeInterval? {
        guard let raw = stringValue("ScreenshotTimerSeconds"),
              let value = Double(raw),
              value.isFinite,
              value > 0 else { return nil }
        return value
    }

    /// `-ScreenshotTimerName=…` — display name for screenshot timer.
    static var screenshotTimerName: String? {
        stringValue("ScreenshotTimerName")
    }

    /// `-ScreenshotShoppingSeed=label|!purchased|…` — pipe-separated shopping rows.
    /// Prefix `!` marks purchased. Optional ` — recipeName` (em dash) after the label.
    static var screenshotShoppingSeed: String? {
        stringValue("ScreenshotShoppingSeed")
    }

    /// `-StartDescriptionEdit=1` — opens description WKWebView editor (requires edit mode + v3).
    static var startDescriptionEdit: Bool {
        boolFlag("StartDescriptionEdit")
    }

    /// `-DescriptionEditorSimulateText=.` — after editor ready, inserts text (verify scripts only).
    static var simulateDescriptionEditorText: String? {
        stringValue("DescriptionEditorSimulateText")
    }

    /// `-DescriptionEditorSimulateCommand=bold|bulletList|...` — after editor ready,
    /// runs a formatting command to exercise the incremental reconcile sync (verify scripts only).
    static var simulateDescriptionEditorCommand: String? {
        stringValue("DescriptionEditorSimulateCommand")
    }

    /// `-SimulateErrorAlert=1` — presents `errorAlert` on shopping list (verify scripts).
    static var simulateErrorAlert: Bool {
        boolFlag("SimulateErrorAlert")
    }

    /// `-OpenTab=shopping|discover|recipes|profile|import`
    static var openTab: AppTab? {
        guard let raw = stringValue("OpenTab") else { return nil }
        switch raw {
        case "discover": return .discover
        case "import": return .importTab
        case "recipes": return .recipes
        case "shopping": return .shopping
        case "profile": return .profile
        default: return nil
        }
    }

    /// Apply `-AppLanguage=` / `-AppTheme=` before SwiftUI bodies evaluate localized strings.
    static func applyScreenshotPreferences() {
        if let raw = stringValue("AppLanguage"),
           let language = AppLanguagePreference(rawValue: raw) {
            AppLanguagePreference.save(language)
        }
        if let raw = stringValue("AppTheme"),
           let theme = AppThemePreference(rawValue: raw) {
            AppThemePreference.save(theme)
        }
    }

    /// Start / replace screenshot timer once TimerManager is ready.
    /// When `-ScreenshotCapture=1` is set without timer seconds, clear leftover timers
    /// so Discover / shopping / recipes shots stay clean.
    @MainActor
    static func applyScreenshotTimerIfNeeded(timerManager: TimerManager) {
        guard screenshotCapture || screenshotTimerSeconds != nil else { return }
        clearDeliveredNotifications()
        for timer in timerManager.activeTimers {
            timerManager.deleteTimer(id: timer.id)
        }
        guard let seconds = screenshotTimerSeconds else {
            // Sync may restore remote timers after the first clear — sweep again.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                clearDeliveredNotifications()
                for timer in timerManager.activeTimers {
                    timerManager.deleteTimer(id: timer.id)
                }
            }
            return
        }
        let name = (screenshotTimerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        _ = timerManager.createAndStartTimer(
            name: name.isEmpty ? "Timer" : name,
            duration: seconds,
            type: .seconds
        )
    }

    /// Replace shopping list from `-ScreenshotShoppingSeed=` (manifest `!` = purchased).
    @MainActor
    static func applyScreenshotShoppingSeedIfNeeded(syncService: YjsSyncService) async {
        guard let raw = screenshotShoppingSeed, !raw.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var items: [ShoppingListItem] = []
        for part in raw.split(separator: "|", omittingEmptySubsequences: false) {
            var token = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            var purchased = false
            if token.hasPrefix("!") {
                purchased = true
                token = String(token.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let label: String
            let recipeName: String
            if let range = token.range(of: " — ") {
                label = String(token[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                recipeName = String(token[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let range = token.range(of: " - ") {
                label = String(token[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                recipeName = String(token[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                label = token
                recipeName = ""
            }
            guard !label.isEmpty else { continue }
            items.append(
                ShoppingListItem(
                    label: label,
                    recipeName: recipeName,
                    purchased: purchased,
                    purchasedAt: purchased ? now : nil,
                    createdAt: now
                )
            )
        }
        do {
            try await syncService.replaceShoppingItems(items)
        } catch {
            AppLog.error(.sync, "screenshot_shopping_seed_failed", data: ["error": "\(error)"])
        }
    }

    private static func clearDeliveredNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Parsing helpers

    private static func boolFlag(_ name: String) -> Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-\(name)=1" || arg == "-\(name)" { return true }
            if arg.hasPrefix("-\(name)=") {
                let value = String(arg.dropFirst(name.count + 2))
                return value == "1" || value.lowercased() == "true"
            }
        }
        return false
    }

    private static func stringValue(_ name: String) -> String? {
        let prefix = "-\(name)="
        for arg in ProcessInfo.processInfo.arguments {
            guard arg.hasPrefix(prefix) else { continue }
            let value = String(arg.dropFirst(prefix.count))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
#endif
