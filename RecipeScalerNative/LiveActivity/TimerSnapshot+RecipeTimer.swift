//
//  TimerSnapshot+RecipeTimer.swift
//  RecipeScalerNative
//
//  Bridges SwiftData `RecipeTimer` → `RecipeScalerCore.TimerSnapshot`.
//  Lives in the main app because `RecipeTimer` is a SwiftData @Model
//  not visible to the `RecipeScalerCore` framework.
//
//  Spec 030 — used by `TimerManager.persistTimerSnapshot()` whenever a timer mutates.
//

import Foundation
import RecipeScalerCore

extension TimerSnapshot {
    /// Build a snapshot from a SwiftData timer. Returns `nil` when the timer
    /// is stopped/idle. Overdue running timers stay visible (`phase == .exceeded`)
    /// — same rule as Live Activity (`remaining < 0 && isRunning`).
    init?(from timer: RecipeTimer) {
        let phase: TimerSnapshotPhase
        let endDate: Date?
        let pausedSeconds: Int?

        if timer.isPaused {
            phase = .paused
            endDate = nil
            pausedSeconds = Int(timer.remainingTime ?? 0)
        } else if timer.isRunning, let endTime = timer.endTime {
            let remainingNow = Int(endTime.timeIntervalSinceNow.rounded())
            phase = remainingNow < 0 ? .exceeded : .running
            endDate = endTime
            pausedSeconds = nil
        } else {
            return nil
        }

        self.init(
            id: timer.id,
            name: timer.name,
            recipeId: timer.recipeId,
            recipeName: timer.recipeDisplayName,
            endDate: endDate,
            pausedRemainingSeconds: pausedSeconds,
            phase: phase,
            totalDurationSeconds: timer.duration
        )
    }
}

extension Array where Element == RecipeTimer {
    /// Build the widget document, applying the same ordering as the mobile panel:
    /// running first, then by ascending remaining seconds. Capped at 4 entries —
    /// the widget never renders more than 4 timers anyway.
    func timerSnapshotDocument(now: Date = Date()) -> TimerSnapshotDocument {
        let sorted = TimerUtils.sortTimers(self)
        var snapshots: [TimerSnapshot] = []
        for timer in sorted {
            if let snapshot = TimerSnapshot(from: timer) {
                snapshots.append(snapshot)
                if snapshots.count == 4 { break }
            }
        }
        return TimerSnapshotDocument(timers: snapshots, generatedAt: now)
    }
}
