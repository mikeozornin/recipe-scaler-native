//
//  NotAuthorizedStateView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — shown when no userId is stored on the watch (user logged out
//  on iPhone, or watch app launched before first WatchConnectivity transfer).
//

import SwiftUI

struct NotAuthorizedStateView: View {
    var body: some View {
        List {
            Section {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: WatchTimerLayout.stateStackSpacing) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .font(.system(size: WatchTimerLayout.stateIconSize))
                                .foregroundStyle(.secondary)
                            VStack(spacing: WatchTimerLayout.stateSubtitleSpacing) {
                                Text(LocalizedStringKey("watch.timer.not-authorized.title"))
                                    .timerSans(WatchTimerLayout.nameFontSize)
                                Text(LocalizedStringKey("watch.timer.not-authorized.subtitle"))
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
    NotAuthorizedStateView()
}
