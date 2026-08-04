//
//  SharedDeviceId.swift
//  RecipeScalerCore
//
//  Spec 030 Phase B2 — device_id shared between the main app and extensions
//  (WidgetPushHandler registers from HomeWidgetExtension; registrar body needs
//  the same id as TimerSyncService / PushRegistrationService).
//

import Foundation

public enum SharedDeviceId {
    /// Main-app / sync UserDefaults key (legacy; kept for TimerSyncService parity).
    public static let standardKey = "deviceId"

    /// App Group key so the widget extension can read the same id.
    public static let appGroupKey = "shared.deviceId"

    /// Stable per-install device id. Mirrors between `UserDefaults.standard` and
    /// the App Group suite so extension processes see the same value.
    public static func current() -> String {
        if let id = UserDefaults.standard.string(forKey: standardKey), !id.isEmpty {
            AppGroup.userDefaults?.set(id, forKey: appGroupKey)
            return id
        }
        if let id = AppGroup.userDefaults?.string(forKey: appGroupKey), !id.isEmpty {
            UserDefaults.standard.set(id, forKey: standardKey)
            return id
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: standardKey)
        AppGroup.userDefaults?.set(newId, forKey: appGroupKey)
        return newId
    }
}
