//
//  SharedAuthStore.swift
//  RecipeScalerNative
//
//  Shim: re-exports SharedAuthStore from RecipeScalerCore framework.
//  Once RecipeScalerCore target is created in Xcode and this file is removed
//  from the main app compile sources, add `import RecipeScalerCore` instead.
//

import Foundation

// MARK: - SharedAuthStore (App Group mirror)
// Duplicated here until RecipeScalerCore framework target is set up in Xcode.
// The canonical copy lives at RecipeScalerCore/Auth/SharedAuthStore.swift.

public enum SharedAuthStore {
    /// App Group identifier shared between main app and extensions.
    public static let appGroupID = "group.ru.recipescaler.RecipeScalerNative"

    /// UserDefaults key for the currently authenticated user identifier.
    public static let userIdKey = "shared.userId"

    /// Currently authenticated user identifier, or `nil` when the user is signed out.
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
