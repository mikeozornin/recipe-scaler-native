//
//  TimerLiveActivityActionQueue.swift
//  RecipeScalerNative
//

import Foundation

enum TimerLiveActivityAction: String, Codable, Sendable {
    case pause
    case resume
}

private func timerLiveActivityDarwinCallback(
    _: CFNotificationCenter?,
    _: UnsafeMutableRawPointer?,
    _: CFNotificationName?,
    _: UnsafeRawPointer?,
    _: CFDictionary?
) {
    Task { @MainActor in
        TimerLiveActivityActionQueue.drainIfNeeded()
    }
}

/// App Group bridge: Live Activity intents (extension) → main app `TimerManager`.
enum TimerLiveActivityActionQueue {
    static let appGroupID = "group.ru.recipescaler.RecipeScalerNative"
    private static let pendingKey = "timerLiveActivity.pendingAction"
    private static let notificationNameString = "com.recipescaler.timerLiveActivity.action" as CFString
    private static let notificationName = CFNotificationName(notificationNameString)

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    @MainActor
    private static var handler: (@Sendable (TimerLiveActivityAction, String) -> Void)?

    @MainActor
    static func installHandler(_ handler: @escaping @Sendable (TimerLiveActivityAction, String) -> Void) {
        self.handler = handler
        installDarwinObserverIfNeeded()
    }

    static func enqueue(action: TimerLiveActivityAction, timerId: String) {
        guard let defaults else { return }
        let payload: [String: String] = [
            "action": action.rawValue,
            "timerId": timerId,
        ]
        defaults.set(payload, forKey: pendingKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }

    @MainActor
    static func drainIfNeeded() {
        guard let defaults,
              let payload = defaults.dictionary(forKey: pendingKey) as? [String: String],
              let actionRaw = payload["action"],
              let action = TimerLiveActivityAction(rawValue: actionRaw),
              let timerId = payload["timerId"],
              !timerId.isEmpty else {
            return
        }
        defaults.removeObject(forKey: pendingKey)
        handler?(action, timerId)
    }

    @MainActor
    private static var didInstallObserver = false

    @MainActor
    private static func installDarwinObserverIfNeeded() {
        guard !didInstallObserver else { return }
        didInstallObserver = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            timerLiveActivityDarwinCallback,
            notificationNameString,
            nil,
            .deliverImmediately
        )
    }
}
