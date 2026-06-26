//
//  ErrorStateView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — error state (not connected to phone). Square icon+text block,
//  single-line title below the icon, Settings button as a sibling below
//  the square.
//
//  Figma node 132:922 / 132:934.
//

import SwiftUI

struct ErrorStateView: View {
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
            Image(systemName: "iphone.gen2.slash")
                .font(.system(size: WatchTimerLayout.stateIconSize, weight: .medium))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey("watch.timer.error.title"))
                .timerSans(WatchTimerLayout.stateTitleFontSize)
                .multilineTextAlignment(.center)
        }
        .frame(width: width, height: width)
    }
}

#Preview {
    ErrorStateView()
}
