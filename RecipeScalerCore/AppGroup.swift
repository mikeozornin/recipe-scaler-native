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
    public static let id = "group.ru.recipescaler.RecipeScaler"

    /// Convenience accessor for the shared `UserDefaults` suite.
    public static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: id)
    }
}
