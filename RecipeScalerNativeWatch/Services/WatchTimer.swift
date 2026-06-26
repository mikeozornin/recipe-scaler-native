//
//  WatchTimer.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — watch-side timer model. Wraps the Core `ServerActiveTimer`
//  payload with view-friendly computed properties (palette resolution,
//  live countdown source, action icon).
//

import Foundation
import RecipeScalerCore

struct WatchTimer: Identifiable, Equatable {
    let id: String
    var name: String
    let duration: Int
    var endDate: Date?
    var isPaused: Bool
    var pausedRemainingSeconds: Int?
    var lastUpdated: Int64

    init(server: ServerActiveTimer) {
        self.id = server.timerId
        self.name = server.name
        self.duration = server.duration
        self.endDate = server.endTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        self.isPaused = server.isPaused
        self.pausedRemainingSeconds = server.isPaused ? server.remainingSeconds() : nil
        self.lastUpdated = server.lastUpdated
    }

    var presentationState: ActiveTimerState {
        ActiveTimerState(
            duration: duration,
            endDate: endDate,
            isPaused: isPaused,
            pausedRemainingSeconds: pausedRemainingSeconds
        )
    }
}

extension WatchTimer {
    /// Remaining seconds at the given time. Negative when exceeded.
    func remainingSeconds(now: Date) -> Int {
        ActiveTimerPresentation.remainingSeconds(presentationState, now: now)
    }

    func progressFraction(now: Date) -> Double {
        ActiveTimerPresentation.progressFraction(presentationState, now: now)
    }

    /// SF Symbol name for the action the user can take (not the status).
    /// - Running timer → user can pause → `pause.fill`.
    /// - Paused timer  → user can resume → `play.fill`.
    var actionIcon: String {
        isPaused ? "play.fill" : "pause.fill"
    }

    func snapshotPhase(now: Date) -> TimerSnapshotPhase {
        ActiveTimerPresentation.snapshotPhase(presentationState, now: now)
    }

    func palette(at now: Date) -> TimerPalette {
        ActiveTimerPresentation.palette(presentationState, now: now)
    }
}
