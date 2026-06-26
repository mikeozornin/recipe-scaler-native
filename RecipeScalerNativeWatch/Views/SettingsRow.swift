//
//  SettingsRow.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — Settings button shown at the bottom of every state's List.
//  Reserved for future functionality — tap is a no-op with a light haptic.
//

import SwiftUI

struct SettingsRow: View {
    var body: some View {
        Button {
            WatchHaptics.click()
        } label: {
            Label(
                LocalizedStringKey("watch.timer.settings.label"),
                systemImage: "gear"
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, minHeight: WatchTimerLayout.settingsHeight)
        .accessibilityHint(Text(LocalizedStringKey("watch.timer.settings.hint")))
    }
}

#Preview {
    SettingsRow()
        .frame(width: 179)
}
