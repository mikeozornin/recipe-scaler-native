//
//  SharedAuthStore.swift
//  RecipeScalerCore
//
//  Shared storage for auth credentials (userId) accessible from
//  the main app and the Share/Action extensions via App Group.
//

import Foundation

public enum SharedAuthStore {
    /// App Group identifier shared between main app and extensions.
    /// Must be configured in entitlements for every target that uses this store.
    public static let appGroupID = "group.ru.recipescaler.RecipeScalerNative"

    /// UserDefaults key for the currently authenticated user identifier.
    public static let userIdKey = "shared.userId"

    /// Currently authenticated user identifier, or `nil` when the user is signed out.
    ///
    /// Writes propagate to all processes in the App Group (main app + extensions).
    /// On the simulator, `UserDefaults(suiteName:)` works for any suite name, so
    /// this property is testable without a real provisioning profile.
    public static var userId: String? {
        get { UserDefaults(suiteName: appGroupID)?.string(forKey: userIdKey) }
        set {
            let defaults = UserDefaults(suiteName: appGroupID)
            if let newValue {
                defaults?.set(newValue, forKey: userIdKey)
            } else {
                defaults?.removeObject(forKey: userIdKey)
            }
        }
    }

    /// Remove the stored user identifier. Called on logout.
    public static func clear() {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: userIdKey)
    }
}
