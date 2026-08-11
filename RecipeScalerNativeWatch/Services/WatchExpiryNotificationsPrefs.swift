//
//  WatchExpiryNotificationsPrefs.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 062 — user-facing toggle "Haptics when timer expires".
//  Persisted in watch-local UserDefaults, default ON.
//

import Foundation

enum WatchExpiryNotificationsPrefs {
    static let defaultsKey = "watchExpiryNotificationsEnabled"

    static let didChangeNotification = Notification.Name("WatchExpiryNotificationsPrefsDidChange")

    static var isEnabled: Bool {
        // Must use bool(forKey:) — `object(forKey:) as? Bool` fails for stored
        // `false` (bridged as NSNumber), so OFF always read back as default true.
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
        NotificationCenter.default.post(
            name: didChangeNotification,
            object: nil,
            userInfo: ["isEnabled": value]
        )
    }

    /// Idempotent; call from app init.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [defaultsKey: true])
    }
}
