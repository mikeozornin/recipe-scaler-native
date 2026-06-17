//
//  WidgetTimerAccent.swift
//  HomeWidgetExtension
//
//  Spec 030 — accent resolution for the TimerWidget.
//
//  Mirrors the rule from `TimerLiveActivityAccent` so the widget and Live Activity
//  agree on when a timer is "normal / soon / exceeded".
//

import SwiftUI
import RecipeScalerCore

enum WidgetTimerAccent {
    case normal
    case soon
    case exceeded

    /// Single color applied to every element of a timer cell (ring, progress arc,
    /// countdown text, recipe label). Keeps the visual language unified.
    var color: Color {
        switch self {
        case .normal:   return Color(.label)
        case .soon:     return Color.orange
        case .exceeded: return Color(red: 0.98, green: 0.153, blue: 0.188)
        }
    }

    static func resolve(
        phase: TimerSnapshotPhase,
        remainingSeconds: Int,
        totalDuration: TimeInterval
    ) -> Self {
        switch phase {
        case .exceeded:
            return .exceeded
        case .paused, .running:
            if remainingSeconds < 0 { return .exceeded }
            if totalDuration > 0, remainingSeconds < Int(totalDuration) / 10 { return .soon }
            return .normal
        }
    }
}
