//
//  TimerLiveActivityPalette.swift
//  RecipeScalerNative
//

import SwiftUI

/// Colors for the Lock Screen Live Activity card.
/// Lock Screen Live Activity cards always render with a light platter background,
/// so we use hardcoded dark colors — xcassets color sets may resolve incorrectly
/// in the chronod widget extension process.
enum TimerLiveActivityPalette {
    static let label         = Color(red: 0.11, green: 0.11, blue: 0.11) // #1c1c1c
    static let secondaryLabel = Color(red: 0.42, green: 0.42, blue: 0.42) // #6b6b6b
    static let progressTrack  = Color.black.opacity(0.22) // rgba(0,0,0,0.22)

    static func accentColor(for accent: TimerLiveActivityAccent) -> Color {
        switch accent {
        case .normal:   return label
        case .soon:     return .orange
        case .exceeded: return Color(red: 0.98, green: 0.153, blue: 0.188)
        }
    }
}
