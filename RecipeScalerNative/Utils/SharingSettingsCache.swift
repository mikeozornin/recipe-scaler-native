//
//  SharingSettingsCache.swift
//  RecipeScalerNative
//

import Foundation

/// Persists the last-known public-profile sharing settings so the share sheet
/// can build the correct URL even before the network request completes (or when offline).
enum SharingSettingsCache {
    private static let defaults = UserDefaults.standard

    private static let keyPublicProfileEnabled = "sharingCache.publicProfileEnabled"
    private static let keyShareMode            = "sharingCache.shareMode"
    private static let keyUsername             = "sharingCache.username"

    // MARK: - Read

    static var publicProfileEnabled: Bool {
        defaults.bool(forKey: keyPublicProfileEnabled)
    }

    static var shareMode: PublicShareMode {
        guard let raw = defaults.string(forKey: keyShareMode),
              let mode = PublicShareMode(rawValue: raw) else {
            return .one_by_one
        }
        return mode
    }

    static var username: String {
        defaults.string(forKey: keyUsername) ?? ""
    }

    // MARK: - Write

    static func save(publicProfileEnabled: Bool, shareMode: PublicShareMode, username: String) {
        defaults.set(publicProfileEnabled, forKey: keyPublicProfileEnabled)
        defaults.set(shareMode.rawValue, forKey: keyShareMode)
        defaults.set(username, forKey: keyUsername)
    }
}
