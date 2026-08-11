//
//  WatchNotificationDelegate.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 062 — `UNUserNotificationCenterDelegate` for the watch app.
//  When a UNCalendarNotificationTrigger (identifier `watch-timer-<id>-complete`)
//  fires while the app is foreground, suppress the visual banner and sound —
//  the foreground haptic from `TimerListViewModel.checkForExpirations` already
//  covers it (or will, within the next 15s poll cycle).
//

import Foundation
import UserNotifications

final class WatchNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Foreground suppression: no banner, no sound, no list entry.
        // The system haptic for the alert still plays once; this is acceptable
        // because the foreground poll-based haptic may have already fired or
        // is about to fire.
        completionHandler([])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
