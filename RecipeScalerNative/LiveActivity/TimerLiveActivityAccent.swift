//
//  TimerLiveActivityAccent.swift
//  RecipeScalerNative
//

import SwiftUI

enum TimerLiveActivityAccent {
    case normal
    case soon
    case exceeded

    var color: Color {
        TimerLiveActivityPalette.accentColor(for: self)
    }

    var progressFillColor: Color {
        color
    }

    static func resolve(remainingSeconds: Int, totalDuration: TimeInterval) -> Self {
        if remainingSeconds < 0 { return .exceeded }
        // TP14 [review #14]: guard NaN/Inf before Int cast. Inline because
        // this file is compiled into TimerLiveActivityExtension, which can't
        // import SafeIntCasts from the main app target.
        guard totalDuration.isFinite, totalDuration < Double(Int.max) else { return .normal }
        if totalDuration > 0, remainingSeconds < Int(totalDuration) / 10 { return .soon }
        return .normal
    }

    static func resolve(state: RecipeTimerActivityAttributes.ContentState) -> Self {
        resolve(
            remainingSeconds: state.remainingSeconds(),
            totalDuration: state.totalDuration
        )
    }
}
