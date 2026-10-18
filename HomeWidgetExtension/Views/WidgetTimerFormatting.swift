//
//  WidgetTimerFormatting.swift
//  HomeWidgetExtension
//
//  Spec 030 — countdown label formatting for rings and linear rows.
//

import Foundation
import CoreGraphics
import RecipeScalerCore

enum WidgetTimerFormatting {
    /// Compact label: `4m`, `45m`, `35s`, `1,8h`, `2h`, `12h` — lowercase unit suffix, no spaces.
    /// Hours round to one decimal in the current locale (`1h47m` → `1,8h`); whole
    /// values and two-digit hours drop the decimal, so labels still fit in rings.
    static func compactRemaining(seconds: Int) -> String {
        let negative = seconds < 0
        let absSeconds = Swift.abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let secs = absSeconds % 60

        let body: String
        if hours > 0 {
            let tenths = (Double(absSeconds) / 360).rounded() / 10
            let value = tenths >= 10 ? tenths.rounded() : tenths
            body = "\(value.formatted(.number.precision(.fractionLength(0...1))))h"
        } else if minutes > 0 {
            body = "\(minutes)m"
        } else {
            body = "\(secs)s"
        }
        return negative ? "-\(body)" : body
    }

    /// Paused (and linear-row static) clock: `4:05`, `1:02:03`.
    static func shortClock(_ seconds: Int) -> String {
        let absSeconds = Swift.abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let secs = absSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Paused ring clock: `4:05` under an hour, then the running label (`1,8h`) —
    /// `1:47:28` does not fit inside the 56pt ring.
    static func ringClock(_ seconds: Int) -> String {
        let absSeconds = Swift.abs(seconds)
        guard absSeconds >= 3600 else { return shortClock(absSeconds) }
        return compactRemaining(seconds: absSeconds)
    }

    /// Seconds left before switching from minute labels (`Nm`) to second labels (`Ns`).
    static let liveCountdownThresholdSeconds = 60
}

extension TimerSnapshot {
    /// Elapsed / total, clamped to `[0, 1]`.
    ///
    /// Spec 030 originally defined this here; spec 039 moved it to
    /// `RecipeScalerCore/TimerViews/TimerFormatting.swift` so the watch app
    /// can share it. This widget-side stub has been removed — callers use the
    /// Core extension via `import RecipeScalerCore`.
}
