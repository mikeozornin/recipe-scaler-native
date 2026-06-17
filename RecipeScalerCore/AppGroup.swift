//
//  AppGroup.swift
//  RecipeScalerCore
//
//  Canonical App Group identifier shared between the main app, extensions,
//  and frameworks. Use `AppGroup.id` instead of hardcoding the literal string.
//
//  Existing `SharedAuthStore.appGroupID` and other wrappers are expected to
//  migrate to this constant over time; both are kept in sync via the same
//  literal value to avoid breaking changes during the rollout.
//

import Foundation

public enum AppGroup {
    /// App Group identifier shared between the main app and all extensions.
    ///
    /// Must be configured in the target's entitlements file:
    /// `com.apple.security.application-groups = [group.ru.recipescaler.RecipeScalerNative]`
    ///
    /// Currently consumed by:
    /// - `SharedAuthStore` (auth user id)
    /// - `ShoppingListSnapshotStore` (shopping list snapshot for App Intents)
    /// - `RecipeSnapshotStore` (recipe list for App Intents)
    /// - `TimerLiveActivityActionQueue` (extension → app action bridge)
    /// - `TimerLiveActivityMetadataProvider` (recipe thumbnails)
    /// - `TimerSnapshotStore` (timer snapshot for HomeWidgetExtension)
    public static let id = "group.ru.recipescaler.RecipeScalerNative"

    /// Convenience accessor for the shared `UserDefaults` suite.
    public static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: id)
    }
}
