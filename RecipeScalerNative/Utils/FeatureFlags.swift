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
    /// OFF by default. Enable for development:
    ///   `defaults write ru.recipescaler.RecipeScaler featureAdoptionGuides -bool YES`
    static var featureAdoptionGuidesEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.featureAdoptionGuidesKey) as? Bool ?? false
    }

    /// UserDefaults key. Callers should not read it directly — use
    /// `featureAdoptionGuidesEnabled` for clarity.
    static let featureAdoptionGuidesKey = "featureAdoptionGuides"
}
