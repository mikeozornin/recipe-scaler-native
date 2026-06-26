//
//  ActiveTimerPresentation.swift
//  RecipeScalerCore
//
//  Pure presentation math for active timers (watch, tests, future surfaces).
//  Single source of truth for remaining, progress, phase, and palette.
//

import Foundation

/// Minimal timer state needed to render countdown UI at an arbitrary `now`.
public struct ActiveTimerState: Sendable, Equatable {
    public let duration: Int
    public let endDate: Date?
    public let isPaused: Bool
    public let pausedRemainingSeconds: Int?

    public init(
        duration: Int,
        endDate: Date?,
        isPaused: Bool,
        pausedRemainingSeconds: Int?
    ) {
        self.duration = duration
        self.endDate = endDate
        self.isPaused = isPaused
        self.pausedRemainingSeconds = pausedRemainingSeconds
    }

    public init(server: ServerActiveTimer, now: Date = Date()) {
        duration = server.duration
        endDate = server.endTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        isPaused = server.isPaused
        pausedRemainingSeconds = server.isPaused ? server.remainingSeconds(at: now) : nil
    }
}

public enum ActiveTimerPresentation {
    /// Remaining seconds at `now`. Negative when exceeded.
    public static func remainingSeconds(_ state: ActiveTimerState, now: Date) -> Int {
        if state.isPaused, let remaining = state.pausedRemainingSeconds { return remaining }
        guard let endDate = state.endDate else { return 0 }
        return Int(endDate.timeIntervalSince(now))
    }

    /// Elapsed / duration in `[0, 1]`. Stays at `1` once exceeded.
    public static func progressFraction(_ state: ActiveTimerState, now: Date) -> Double {
        guard state.duration > 0 else { return 0 }
        let remaining = remainingSeconds(state, now: now)
        if !state.isPaused, remaining <= 0 { return 1 }
        let elapsed = Double(state.duration) - Double(remaining)
        return min(max(elapsed / Double(state.duration), 0), 1)
    }

    public static func snapshotPhase(_ state: ActiveTimerState, now: Date) -> TimerSnapshotPhase {
        if state.isPaused { return .paused }
        if remainingSeconds(state, now: now) < 0 { return .exceeded }
        return .running
    }

    public static func palette(_ state: ActiveTimerState, now: Date) -> TimerPalette {
        TimerPalette.resolve(
            phase: snapshotPhase(state, now: now),
            remainingSeconds: remainingSeconds(state, now: now),
            totalDuration: TimeInterval(state.duration)
        )
    }
}
