//
//  LegacyAuthBannerReminder.swift
//  RecipeScalerNative
//
//  Local dismiss state for legacy auth grace banner (parity with web).
//

import Foundation

enum LegacyAuthBannerReminder {
    private static let dismissPrefix = "legacy-auth-banner-dismissed-until-"
    private static let oneWeek: TimeInterval = 7 * 24 * 60 * 60

    private static func dismissKey(userId: String) -> String {
        "\(dismissPrefix)\(userId)"
    }

    static func shouldShow(userId: String) -> Bool {
        guard let until = UserDefaults.standard.string(forKey: dismissKey(userId: userId)) else {
            return true
        }
        guard let date = ISO8601DateFormatter().date(from: until) else {
            return true
        }
        return Date() >= date
    }

    static func postpone(userId: String) {
        let next = Date().addingTimeInterval(oneWeek)
        let iso = ISO8601DateFormatter().string(from: next)
        UserDefaults.standard.set(iso, forKey: dismissKey(userId: userId))
    }
}