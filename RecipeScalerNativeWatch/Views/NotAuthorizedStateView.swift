//
//  NotAuthorizedStateView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — shown when no userId is stored on the watch (user logged out
//  on iPhone, or watch app launched before first WatchConnectivity transfer).
//  Not in Figma — composed by the same rule as Empty/Error.
//

import SwiftUI

struct NotAuthorizedStateView: View {
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: WatchTimerLayout.stateToSettingsSpacing) {
                Spacer(minLength: 0)
                stateSquare(width: geo.size.width)
                Spacer(minLength: 0)
                SettingsRow()
            }
            .frame(width: geo.size.width)
        }
    }

    /// Square icon+text block — side equals the content width.
    @ViewBuilder
    private func stateSquare(width: CGFloat) -> some View {
        VStack(spacing: WatchTimerLayout.stateStackSpacing) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: WatchTimerLayout.stateIconSize, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(spacing: WatchTimerLayout.stateSubtitleSpacing) {
                Text(LocalizedStringKey("watch.timer.not-authorized.title"))
                    .timerSans(WatchTimerLayout.stateTitleFontSize)
                Text(LocalizedStringKey("watch.timer.not-authorized.subtitle"))
                    .timerSans(WatchTimerLayout.stateTitleFontSize)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(width: width, height: width)
    }
}

#Preview {
    NotAuthorizedStateView()
}
