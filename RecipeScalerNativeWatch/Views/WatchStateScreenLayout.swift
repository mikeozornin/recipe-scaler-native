//
//  WatchStateScreenLayout.swift
//  RecipeScalerNativeWatch Watch App
//
//  Shared layout for Empty / Error / NotAuthorized: icon+title centered in
//  the space above the Settings button (Settings pinned to the bottom).
//

import SwiftUI

struct WatchStateScreenLayout<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                VStack(spacing: WatchTimerLayout.stateStackSpacing) {
                    content()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                SettingsRow()
                    .padding(.top, WatchTimerLayout.stateToSettingsSpacing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
