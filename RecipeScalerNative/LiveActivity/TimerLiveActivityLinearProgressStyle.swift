//
//  TimerLiveActivityLinearProgressStyle.swift
//  RecipeScalerNative
//

import SwiftUI

/// Styles `ProgressView(timerInterval:)` for Lock Screen Live Activity.
/// Custom styles must wrap `ProgressView(configuration)` — `fractionCompleted` is not
/// available for date ranges, but system timer animation still runs.
struct TimerLiveActivityLinearProgressStyle: ProgressViewStyle {
    var fillColor: Color
    var barHeight: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration)
            .progressViewStyle(.linear)
            .tint(fillColor)
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
            .scaleEffect(x: 1, y: barHeight / 2, anchor: .center)
    }
}
