//
//  RemindersSyncPreferences.swift
//  RecipeScalerNative
//

import Foundation

/// User preferences for the Apple Reminders sync feature.
///
/// Stored in `UserDefaults.standard`. The feature is opt-in and disabled by default.
enum RemindersSyncPreferences {

    // MARK: - Storage keys

    private static let enabledKey = "remindersSyncEnabled"
    private static let listIdentifierKey = "remindersListIdentifier"

    /// Sentinel value meaning: create (or reuse) the dedicated «Recipe Scaler» list.
    static let dedicatedListSentinel = "__rs_create_dedicated__"

    // MARK: - Sync enabled toggle

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    // MARK: - Chosen list identifier

    /// Returns the stored `EKCalendar.calendarIdentifier`, or `dedicatedListSentinel` when
    /// the user wants a dedicated «Recipe Scaler» list (default).
    static var listIdentifier: String {
        get {
            UserDefaults.standard.string(forKey: listIdentifierKey) ?? dedicatedListSentinel
        }
        set {
            UserDefaults.standard.set(newValue, forKey: listIdentifierKey)
        }
    }

    static var usesDedicatedList: Bool {
        listIdentifier == dedicatedListSentinel
    }
}
