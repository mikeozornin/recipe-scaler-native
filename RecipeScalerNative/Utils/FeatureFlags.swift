//
//  FeatureFlags.swift
//  RecipeScalerNative
//
//  Centralized runtime feature flags. Each flag defaults to a safe value
//  (typically OFF) and can be toggled for development without code changes.
//
//  Spec 040 — `featureAdoptionGuides` is OFF by default so the guide screens
//  ship in the codebase but stay hidden in the app until explicitly enabled.
//

import Foundation

enum FeatureFlags {
    /// Spec 040 — per-item drill-in guides on the Feature Adoption screen.
    /// Release is always off. Debug reads UserDefaults (default off):
    ///   `defaults write ru.recipescaler.RecipeScaler featureAdoptionGuides -bool YES`
    static var featureAdoptionGuidesEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.object(forKey: Self.featureAdoptionGuidesKey) as? Bool ?? false
        #else
        return false
        #endif
    }

    /// Spec 074 — «Начать готовить» / process-table chrome.
    /// Release is always off. Debug stays on unless overridden:
    ///   `defaults write ru.recipescaler.RecipeScaler processTableCooking -bool NO`
    static var processTableCookingEnabled: Bool {
        #if DEBUG
        if let override = UserDefaults.standard.object(forKey: Self.processTableCookingKey) as? Bool {
            return override
        }
        return true
        #else
        return false
        #endif
    }

    /// UserDefaults key. Callers should not read it directly — use
    /// `featureAdoptionGuidesEnabled` for clarity.
    static let featureAdoptionGuidesKey = "featureAdoptionGuides"

    static let processTableCookingKey = "processTableCooking"
}
