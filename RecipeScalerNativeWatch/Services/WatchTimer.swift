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
        self.pausedRemainingSeconds = server.pausedDuration
        self.lastUpdated = server.lastUpdated
    }
}

extension WatchTimer {
    /// Remaining seconds at the given time. Negative when exceeded.
    func remainingSeconds(now: Date) -> Int {
        if isPaused, let r = pausedRemainingSeconds { return r }
        guard let endDate else { return 0 }
        return Int(endDate.timeIntervalSince(now))
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        // Use a synthetic now for snapshot; the view layer passes a real date.
        let now = Date()
        let remaining = Double(remainingSeconds(now: now))
        let elapsed = Double(duration) - remaining
        return min(max(elapsed / Double(duration), 0), 1)
    }

    /// SF Symbol name for the action the user can take (not the status).
    /// - Running timer → user can pause → `pause.fill`.
    /// - Paused timer  → user can resume → `play.fill`.
    var actionIcon: String {
        isPaused ? "play.fill" : "pause.fill"
    }
}
