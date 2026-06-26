//
//  ErrorStateView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — error state (fetch / sync failure). Square icon+text area,
//  two lines of text below the icon, Settings row at the bottom.
//

import SwiftUI

struct ErrorStateView: View {
    var body: some View {
        List {
            Section {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: WatchTimerLayout.stateStackSpacing) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: WatchTimerLayout.stateIconSize))
                                .foregroundStyle(.secondary)
                            VStack(spacing: WatchTimerLayout.stateSubtitleSpacing) {
                                Text(LocalizedStringKey("watch.timer.error.title"))
                                    .timerSans(WatchTimerLayout.nameFontSize)
                                Text(LocalizedStringKey("watch.timer.error.subtitle"))
                                    .timerSans(WatchTimerLayout.nameFontSize)
                                    .foregroundStyle(.secondary)
                            }
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
    ErrorStateView()
}
