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
        WatchStateScreenLayout {
            Image(systemName: "iphone.gen2.slash")
                .font(.system(size: WatchTimerLayout.stateIconSize, weight: .medium))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey("watch.timer.not-authorized.title"))
                .timerSans(WatchTimerLayout.stateTitleFontSize)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    NotAuthorizedStateView()
}
