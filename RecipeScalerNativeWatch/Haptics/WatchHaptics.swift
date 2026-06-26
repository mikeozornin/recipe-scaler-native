//
//  WatchHaptics.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — centralised haptic feedback. Uses `WKInterfaceDevice` only
//  (no UIKit). Called from `TimerListView` swipe actions, Settings tap,
//  and (foreground) timer expiration.
//

import WatchKit

enum WatchHaptics {
    static func click() {
        WKInterfaceDevice.current().play(.click)
    }

    static func success() {
        WKInterfaceDevice.current().play(.success)
    }

    static func notification() {
        WKInterfaceDevice.current().play(.notification)
    }

    /// Timer expired while the app is foreground — 3 .notification haptics
    /// spaced 0.5s apart (matches the iPhone app's pattern).
    static func timerExpired() {
        Task {
            for _ in 0..<3 {
                WKInterfaceDevice.current().play(.notification)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
