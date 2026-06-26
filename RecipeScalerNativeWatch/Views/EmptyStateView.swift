//
//  EmptyStateView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — empty state (no active timers). Square icon+text area whose
//  side equals the available content width, centered vertically within the
//  rectangular watch screen.
//

import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        List {
            Section {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: WatchTimerLayout.stateStackSpacing) {
                            Image(systemName: "timer")
                                .font(.system(size: WatchTimerLayout.stateIconSize))
                                .foregroundStyle(.secondary)
                            Text(LocalizedStringKey("watch.timer.empty.title"))
                                .timerSans(WatchTimerLayout.nameFontSize)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: geo.size.width, height: geo.size.width)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Section {
                SettingsRow()
            }
        }
        .listStyle(.plain)
    }
}

#Preview {
    EmptyStateView()
}
