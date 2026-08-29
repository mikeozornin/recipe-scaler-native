//
//  AppGroup.swift
//  RecipeScalerCore
//
//  Canonical App Group identifier shared between the main app, extensions,
//  and frameworks. Use `AppGroup.id` instead of hardcoding the literal string.
//

import Foundation

public enum AppGroup {
    /// App Group identifier shared between the main app and all extensions.
    ///
    /// Must be configured in the target's entitlements file:
    /// `com.apple.security.application-groups = [group.ru.recipescaler.RecipeScaler]`
    ///
    /// Currently consumed by:
    /// - `SharedAuthStore` (auth user id)
    /// - `ShoppingListSnapshotStore` (shopping list snapshot for App Intents)
    /// - `RecipeSnapshotStore` (recipe list for App Intents)
    /// - `TimerLiveActivityActionQueue` (extension → app action bridge)
    /// - `TimerLiveActivityMetadataProvider` (recipe thumbnails)
    /// - `TimerSnapshotStore` (timer snapshot for HomeWidgetExtension)
    /// - `pendingRecipeIdKey` (Share/Action extension → host recipe hand-off)
    ///
    /// Side-by-side builds (spec 066): the dev flavor (`RS_DEV_FLAVOR`
    /// compilation condition, DebugDevice/ReleaseDevice configurations, scheme
    /// RecipeScalerNative-Dev) uses a `.debug`-suffixed group so the dev
    /// install on the same phone never shares data with the App Store
    /// install. The suffix must match every target's entitlements.
    #if RS_DEV_FLAVOR
    public static let id = "group.ru.recipescaler.RecipeScaler.debug"
    public static let isDevFlavor = true
    #else
    public static let id = "group.ru.recipescaler.RecipeScaler"
    public static let isDevFlavor = false
    #endif

    /// Pending recipe id hand-off from Share/Action extensions to the host app.
    ///
    /// Written by `ShareView.openRecipeInHostApp()` when the user taps "Open"
    /// after a successful import, and read by
    /// `DeepLinkRouter.consumePendingRecipeId()` on the host side (App Group
    /// first, then `UserDefaults.standard` as a legacy fallback).
    ///
    /// Canonical location: both the Share/Action extension targets and the
    /// host app link against `RecipeScalerCore`, so this constant is the
    /// single source of truth for the key string across module boundaries.
    public static let pendingRecipeIdKey = "routing.pendingRecipeId"

    /// Convenience accessor for the shared `UserDefaults` suite.
    public static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: id)
    }
}
