//
//  AppThemePreference.swift
//  RecipeScalerNative
//

import SwiftUI

/// App-wide color scheme (web `ThemeProvider`: system / light / dark).
enum AppThemePreference: String, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    static let storageKey = "appThemePreference"

    static var current: AppThemePreference {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = AppThemePreference(rawValue: raw) else {
            return .system
        }
        return value
    }

    static func save(_ preference: AppThemePreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: storageKey)
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}