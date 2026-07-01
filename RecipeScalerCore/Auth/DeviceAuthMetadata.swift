//
//  DeviceAuthMetadata.swift
//  RecipeScalerCore
//
//  Shared device / platform fields for auth endpoints (spec 041).
//

import Foundation

public enum DeviceAuthMetadata {
    public static let platform = "ios-native"

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    public static var language: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        if preferred.hasPrefix("ru") { return "ru" }
        return "en"
    }

    /// Stable per-install device id (same key as main app sync stack).
    public static func deviceId(defaults: UserDefaults = .standard) -> String {
        let key = "deviceId"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: key)
        return newId
    }
}