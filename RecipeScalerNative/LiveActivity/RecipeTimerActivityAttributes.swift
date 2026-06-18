//
//  RecipeTimerActivityAttributes.swift
//  RecipeScalerNative
//

import ActivityKit
import Foundation

enum TimerActivityPhase: String, Codable, Hashable, Sendable {
    case running
    case paused
    case exceeded
}

struct RecipeTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: TimerActivityPhase
        var endDate: Date?
        var pausedRemainingSeconds: Int
        var startedAt: Date
        var totalDuration: TimeInterval
        var recipeName: String?
        var recipeThumbnailName: String?
        /// Bumped on each coordinator sync so Lock Screen re-renders after extension UI changes.
        var syncedAt: Date
    }

    var timerId: String
    var timerName: String
    var recipeId: String?
}

extension RecipeTimerActivityAttributes.ContentState {
    func remainingSeconds(now: Date = Date()) -> Int {
        switch phase {
        case .paused:
            return pausedRemainingSeconds
        case .exceeded:
            guard let endDate else { return pausedRemainingSeconds }
            // TP14 [review #14]: floor + clamp before Int cast. Inline because
            // this file is shared with TimerLiveActivityExtension, which cannot
            // import SafeIntCasts from the main app target.
            return Self.clampingInt(floor(endDate.timeIntervalSince(now)))
        case .running:
            guard let endDate else { return Self.clampingInt(totalDuration) }
            return Self.clampingInt(floor(endDate.timeIntervalSince(now)))
        }
    }

    /// NaN/Infinity → 0; values outside Int range clamped to the nearest bound.
    /// Local copy of `Int(clampingFinite:)` (this file is compiled into the
    /// Live Activity extension, which can't import `SafeIntCasts.swift`).
    /// See review #14.
    private static func clampingInt(_ value: Double) -> Int {
        if value.isNaN || value.isInfinite { return 0 }
        if value >= Double(Int.max) { return Int.max }
        if value <= Double(Int.min) { return Int.min }
        return Int(value)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        if phase == .exceeded { return 1 }
        let remaining = Double(remainingSeconds())
        let elapsed = totalDuration - remaining
        return min(1, max(0, elapsed / totalDuration))
    }
}
