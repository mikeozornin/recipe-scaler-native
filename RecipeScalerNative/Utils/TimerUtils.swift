//
//  TimerUtils.swift
//  RecipeScalerNative
//
//  Parity with recipe-scaler-web `timer-utils.ts`.
//

import Foundation

enum TimerUtils {
    static func remainingSeconds(for timer: RecipeTimer, now: Date = Date()) -> Int {
        if timer.isPaused {
            return Int(timer.remainingTime ?? 0)
        }
        if !timer.isRunning {
            return Int(timer.duration)
        }
        if let endTime = timer.endTime {
            return Int(floor(endTime.timeIntervalSince(now)))
        }
        return Int(timer.duration)
    }

    static func isTimerCompleted(_ timer: RecipeTimer, now: Date = Date()) -> Bool {
        remainingSeconds(for: timer, now: now) <= 0 && timer.isRunning
    }

    static func formatTime(seconds: Int) -> String {
        let isNegative = seconds < 0
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let secs = absSeconds % 60
        let body: String
        if hours > 0 {
            body = String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            body = String(format: "%02d:%02d", minutes, secs)
        }
        return isNegative ? "-\(body)" : body
    }

    static func sortTimers(_ timers: [RecipeTimer]) -> [RecipeTimer] {
        timers.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning && !rhs.isRunning }
            return remainingSeconds(for: lhs) < remainingSeconds(for: rhs)
        }
    }

    /// Whole seconds shown in the mobile timer panel; also drives `TimerManager` refresh cadence.
    /// Must stay aligned with `MobileTimerPanel` countdown rendering.
    static func panelDisplayedSeconds(for timer: RecipeTimer, now: Date = Date()) -> Int {
        remainingSeconds(for: timer, now: now)
    }

    /// Returns `true` when the panel-visible second changed and `refreshPanelTimers()` should run.
    static func advancePanelDisplayedSecond(
        lastDisplayedSeconds: inout [String: Int],
        timer: RecipeTimer,
        now: Date = Date()
    ) -> Bool {
        let displayedSecond = panelDisplayedSeconds(for: timer, now: now)
        guard lastDisplayedSeconds[timer.id] != displayedSecond else { return false }
        lastDisplayedSeconds[timer.id] = displayedSecond
        return true
    }
}