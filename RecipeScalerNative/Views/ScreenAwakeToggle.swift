//
//  ScreenAwakeToggle.swift
//  RecipeScalerNative
//

import SwiftUI

/// Toolbar control for keep-awake (web `useWakeLock`; SF `play.circle.fill`). State owned by parent screen.
struct ScreenAwakeToggle: View {
    @Binding var isActive: Bool

    var body: some View {
        Button {
            isActive.toggle()
        } label: {
            AppToolbarStyle.iconOnly(systemName: "play.circle.fill", isActive: isActive)
        }
        .appToolbarIconButton()
        .accessibilityIdentifier(AccessibilityIdentifiers.screenAwakeToggle)
        .accessibilityLabel(isActive ? "common.disable-wake-lock" : "common.enable-wake-lock")
    }
}