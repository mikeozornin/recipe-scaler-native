//
//  TimerLiveActivityPalette.swift
//  RecipeScalerNative
//

import SwiftUI

/// Colors for the Lock Screen Live Activity card.
///
/// The Lock Screen Live Activity card uses a solid white background in Light Mode
/// and a solid black background in Dark Mode (per Apple docs). System semantic
/// UIKit colors (`UIColor.label`, `.secondaryLabel`, `.systemFill`) resolve
/// correctly inside the widget extension process and adapt to the current
/// appearance, so we bridge them via `Color(uiColor:)` instead of hardcoding
/// dark RGB values.
enum TimerLiveActivityPalette {
    static let label         = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let progressTrack  = Color(uiColor: .systemFill)

    static func accentColor(for accent: TimerLiveActivityAccent) -> Color {
        switch accent {
        case .normal:   return Color(uiColor: .label)
        case .soon:     return .orange
        case .exceeded: return Color(red: 0.98, green: 0.153, blue: 0.188)
        }
    }
}
