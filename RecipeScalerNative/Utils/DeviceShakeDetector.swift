//
//  DeviceShakeDetector.swift
//  RecipeScalerNative
//
//  Spec 078 — app-wide shake via UIWindow.motionEnded + Notification + debounce.
//

import Foundation
import UIKit

extension Notification.Name {
    /// Posted when the device reports a shake gesture (`UIEvent.EventSubtype.motionShake`).
    static let deviceDidShake = Notification.Name("RecipeScalerNative.deviceDidShake")
}

enum DeviceShakeDetector {
    /// Minimum interval between accepted shakes.
    static let defaultDebounce: TimeInterval = 1.0

    /// Last accepted shake timestamp (monotonic via `Date`).
    private static var lastAcceptedAt: Date?

    /// Test seam: reset debounce clock between unit tests.
    static func resetDebounceForTests() {
        lastAcceptedAt = nil
    }

    /// Returns whether a shake at `now` should fire (updates last-accepted on success).
    @discardableResult
    static func shouldAcceptShake(
        now: Date = Date(),
        debounce: TimeInterval = defaultDebounce
    ) -> Bool {
        if let last = lastAcceptedAt, now.timeIntervalSince(last) < debounce {
            return false
        }
        lastAcceptedAt = now
        return true
    }

    static func postShakeNotification() {
        NotificationCenter.default.post(name: .deviceDidShake, object: nil)
    }
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            DeviceShakeDetector.postShakeNotification()
        }
        super.motionEnded(motion, with: event)
    }
}
