//
//  ScreenAwakeController.swift
//  RecipeScalerNative
//

import UIKit

/// Applies keep-awake via `UIApplication.isIdleTimerDisabled` (web Wake Lock API equivalent).
@MainActor
enum ScreenAwakeController {
    static func setActive(_ active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = active
    }

    static func deactivate() {
        setActive(false)
    }
}