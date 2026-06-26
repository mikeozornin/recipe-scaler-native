//
//  TimerPalette.swift
//  RecipeScalerCore
//
//  Spec 039 — watchOS Timers: color palette shared between watch app and
//  any other surface that renders `TimerSnapshot` without WidgetKit.
//
//  This is the platform-agnostic subset of `WidgetTimerPalette` (which stays
//  in `HomeWidgetExtension` for `WidgetRenderingMode` / `WidgetFamily`
//  handling). Watch and future non-widget surfaces use this type directly.
//

import SwiftUI

/// Palette for rendering `TimerSnapshot`-based UI without WidgetKit.
///
/// Maps a timer's phase + remaining seconds to one of three semantic colors:
///
/// - `normal`   — `Color.primary` (semantic, adapts to light/dark).
/// - `soon`     — orange (`#ff8d28` light / `#ff9230` dark).
/// - `exceeded` — red   (`#fa2730`, parity with `WidgetTimerAccent`).
public struct TimerPalette: Sendable {
    public let accent: Accent

    public init(accent: Accent) {
        self.accent = accent
    }

    /// Resolve palette from a snapshot at a given time.
    public static func resolve(
        phase: TimerSnapshotPhase,
        remainingSeconds: Int,
        totalDuration: TimeInterval
    ) -> TimerPalette {
        TimerPalette(accent: .resolve(
            phase: phase,
            remainingSeconds: remainingSeconds,
            totalDuration: totalDuration
        ))
    }

    /// Foreground color for all timer elements (icon, progress, time, name).
    public var color: Color { accent.color }

    /// Opacity for the unfilled progress track (matches the watch spec token;
    /// the widget keeps its own 0.24 in `WidgetTimerPalette`).
    public static let trackOpacity: Double = 0.4
}

extension TimerPalette {
    public enum Accent: Sendable, Equatable {
        case normal
        case soon
        case exceeded

        public var color: Color {
            switch self {
            case .normal:   return .primary
            case .soon:     return Self.soonColor
            case .exceeded: return Self.exceededColor
            }
        }

        /// Figma `accents/orange` — `#ff8d28` light / `#ff9230` dark.
        /// v1 uses a single value; the system adapts `Color.primary` for the
        /// `normal` case. For `soon` we keep a fixed orange that reads well
        /// on both light and dark backgrounds.
        public static let soonColor = Color(red: 1.0, green: 0.553, blue: 0.157)

        /// Figma `accents/red` — `#fa2730` (parity with `WidgetTimerAccent`).
        public static let exceededColor = Color(red: 0.98, green: 0.153, blue: 0.188)

        /// Same rule as `WidgetTimerAccent.resolve` and `TimerLiveActivityAccent`.
        public static func resolve(
            phase: TimerSnapshotPhase,
            remainingSeconds: Int,
            totalDuration: TimeInterval
        ) -> Self {
            switch phase {
            case .exceeded:
                return .exceeded
            case .paused, .running:
                if remainingSeconds < 0 { return .exceeded }
                guard totalDuration.isFinite, totalDuration > 0,
                      totalDuration < Double(Int.max) else { return .normal }
                let soonThreshold = max(1, Int(totalDuration / 10.0))
                if remainingSeconds <= soonThreshold { return .soon }
                return .normal
            }
        }
    }
}
