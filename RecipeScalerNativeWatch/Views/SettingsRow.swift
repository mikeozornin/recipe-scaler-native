//
//  SettingsRow.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — Settings button shown at the bottom of every state's List.
//  Spec 062 — opens WatchSettingsView (toggle for haptics on completion).
//

import SwiftUI

struct SettingsRow: View {
    var body: some View {
        NavigationLink {
            WatchSettingsView()
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
    NavigationStack {
        SettingsRow()
            .frame(width: 179)
    }
}
