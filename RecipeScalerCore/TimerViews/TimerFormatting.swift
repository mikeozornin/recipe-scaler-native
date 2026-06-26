//
//  TimerFormatting.swift
//  RecipeScalerCore
//
//  Spec 039 — countdown label formatting shared between watch and other
//  non-widget surfaces. Platform-agnostic copy of `WidgetTimerFormatting`
//  (which remains in `HomeWidgetExtension` for the widget only).
//

import Foundation
import CoreGraphics

public enum TimerFormatting {
    /// Compact label: `4m`, `45m`, `35s`, `9h` — lowercase unit suffix, no spaces.
    /// Hours floor to whole hours (`9h45m` → `9h`) so labels fit in rings/rows.
    public static func compactRemaining(seconds: Int) -> String {
        let negative = seconds < 0
        let absSeconds = Swift.abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let secs = absSeconds % 60

        let body: String
        if hours > 0 {
            body = "\(hours)h"
        } else if minutes > 0 {
            body = "\(minutes)m"
        } else {
            body = "\(secs)s"
        }
        return negative ? "-\(body)" : body
    }

    /// Paused (and linear-row static) clock: `4:05`, `1:02:03`.
    public static func shortClock(_ seconds: Int) -> String {
        let absSeconds = Swift.abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let secs = absSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Seconds left before switching from minute labels (`Nm`) to second labels (`Ns`).
    public static let liveCountdownThresholdSeconds = 60
}

extension TimerSnapshot {
    /// Elapsed / total, clamped to `[0, 1]`. Used to drive progress bars and arcs.
    public func progressFraction(now: Date) -> CGFloat {
        guard totalDurationSeconds > 0 else { return 0 }
        let remaining = TimeInterval(remainingSeconds(now: now))
        if phase != .paused, remaining <= 0 { return 1 }
        let elapsed = totalDurationSeconds - remaining
        return CGFloat(min(max(elapsed / totalDurationSeconds, 0), 1))
    }
}
