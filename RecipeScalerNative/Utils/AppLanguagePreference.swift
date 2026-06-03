//
//  AppLanguagePreference.swift
//  RecipeScalerNative
//

import SwiftUI

enum AppLanguagePreference: String, CaseIterable, Identifiable, Hashable {
    case en
    case ru

    var id: String { rawValue }

    static let storageKey = "appLanguage"

    static var current: AppLanguagePreference {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = AppLanguagePreference(rawValue: raw) else {
            return .en
        }
        return value
    }

    static func save(_ language: AppLanguagePreference) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}