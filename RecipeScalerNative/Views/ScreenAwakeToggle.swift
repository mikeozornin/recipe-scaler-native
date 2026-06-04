//
//  ScreenAwakeToggle.swift
//  RecipeScalerNative
//

import SwiftUI

/// Toolbar control for keep-awake (web `useWakeLock` / Coffee icon). State owned by parent screen.
struct ScreenAwakeToggle: View {
    @Binding var isActive: Bool

    var body: some View {
        Button {
            isActive.toggle()
        } label: {
            AppToolbarStyle.iconOnly(.coffee, isActive: isActive)
        }
        .appToolbarIconButton()
        .accessibilityIdentifier(AccessibilityIdentifiers.screenAwakeToggle)
        .accessibilityLabel(
            isActive
                ? String(localized: "common.disable-wake-lock")
                : String(localized: "common.enable-wake-lock")
        )
    }
}