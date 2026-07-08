//
//  ShoppingRemindersTipPreferences.swift
//  RecipeScalerNative
//
//  Permanent dismiss state for the shopping-list Reminders tip banner.
//

import Foundation

enum ShoppingRemindersTipPreferences {
    private static let dismissedKey = "shopping-reminders-tip-dismissed"

    /// Whether the tip may still be shown (ignores Reminders sync enablement — UI layers that).
    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    static func dismiss() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    #if DEBUG
    static func resetForTests() {
        UserDefaults.standard.removeObject(forKey: dismissedKey)
    }
    #endif
}
