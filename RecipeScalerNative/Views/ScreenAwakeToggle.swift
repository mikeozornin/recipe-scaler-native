//
//  ScreenAwakeToggle.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

/// Keeps the screen on while cooking (web `useWakeLock` / `sun.max.fill`).
struct ScreenAwakeToggle: View {
    @State private var isActive = false

    var body: some View {
        Button {
            isActive.toggle()
            UIApplication.shared.isIdleTimerDisabled = isActive
        } label: {
            AppToolbarStyle.iconOnly(
                systemName: "sun.max.fill",
                isActive: isActive
            )
        }
        .appToolbarIconButton()
        .accessibilityLabel(
            isActive
                ? String(localized: "common.disable-wake-lock")
                : String(localized: "common.enable-wake-lock")
        )
        .onDisappear {
            if isActive {
                isActive = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}