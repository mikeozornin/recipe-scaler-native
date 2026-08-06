//
//  AppLanguagePreference.swift
//  RecipeScalerNative
//

import Foundation
import SwiftUI

enum AppLanguagePreference: String, CaseIterable, Identifiable, Hashable {
    case en
    case ru

    var id: String { rawValue }

    static let storageKey = "appLanguage"

    static var current: AppLanguagePreference {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = AppLanguagePreference(rawValue: raw) else {
            return systemDefault
        }
        return value
    }

    /// Follow system language: Russian system → `.ru`, otherwise → `.en`.
    private static var systemDefault: AppLanguagePreference {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang.hasPrefix("ru") ? .ru : .en
    }

    static func save(_ language: AppLanguagePreference) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        apply(language)
    }

    /// Apply the stored preference. Call once at app launch (after `Bundle.installLanguageOverrideSwizzle()`).
    static func bootstrap() {
        Bundle.installLanguageOverrideSwizzle()
        apply(current)
    }

    /// Switch the live language bundle override. Views that already captured strings
    /// (`String(localized:)` resolved at body-eval time) will refresh on the next
    /// SwiftUI re-render — `ContentView` reads the raw value via `@AppStorage`,
    /// which invalidates the tree when the user-facing preference changes.
    static func apply(_ language: AppLanguagePreference) {
        Bundle.setLanguageOverride(language.rawValue)
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}
