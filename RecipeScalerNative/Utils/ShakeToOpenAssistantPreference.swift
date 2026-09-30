//
//  ShakeToOpenAssistantPreference.swift
//  RecipeScalerNative
//
//  Spec 078 — opt-in shake gesture to open the assistant. Default OFF.
//

import Foundation

enum ShakeToOpenAssistantPreference {
    static let storageKey = "shakeToOpenAssistantEnabled"

    /// Test seam; production uses `.standard`.
    static var defaults: UserDefaults = .standard

    /// Missing key → `false` (`UserDefaults.bool(forKey:)`).
    static var isEnabled: Bool {
        get { defaults.bool(forKey: storageKey) }
        set { defaults.set(newValue, forKey: storageKey) }
    }
}
