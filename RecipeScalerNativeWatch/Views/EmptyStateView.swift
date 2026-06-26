//
//  EmptyStateView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — empty state (no active timers). Icon+text centered above
//  Settings; Settings is a sibling pinned to the bottom.
//
//  Figma node 132:758 / 132:918.
//

import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        WatchStateScreenLayout {
            Image(systemName: "timer")
                .font(.system(size: WatchTimerLayout.stateIconSize, weight: .medium))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey("watch.timer.empty.title"))
                .timerSans(WatchTimerLayout.stateTitleFontSize)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    EmptyStateView()
}
