//
//  ScreenAwakeToggle.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

/// Keeps the screen on while cooking (web `useWakeLock` / `cup.and.heat.waves.fill`).
struct ScreenAwakeToggle: View {
    @State private var isActive = false

    var body: some View {
        Button {
            isActive.toggle()
            UIApplication.shared.isIdleTimerDisabled = isActive
        } label: {
            AppSymbol.image("cup.and.heat.waves.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.accentColor)
                .opacity(isActive ? 1 : 0.85)
        }
        .buttonStyle(.plain)
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