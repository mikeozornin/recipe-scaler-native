//
//  ErrorStateView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — error state (not connected to phone). Icon+text centered above
//  Settings; single-line title below the icon.
//
//  Figma node 132:922 / 132:934.
//

import SwiftUI

struct ErrorStateView: View {
    var body: some View {
        WatchStateScreenLayout {
            Image(systemName: "iphone.gen2.slash")
                .font(.system(size: WatchTimerLayout.stateIconSize, weight: .medium))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey("watch.timer.error.title"))
                .timerSans(WatchTimerLayout.stateTitleFontSize)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    ErrorStateView()
}
