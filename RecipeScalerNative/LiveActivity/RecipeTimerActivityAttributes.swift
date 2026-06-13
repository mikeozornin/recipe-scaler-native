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
            return Int(floor(endDate.timeIntervalSince(now)))
        case .running:
            guard let endDate else { return Int(totalDuration) }
            return Int(floor(endDate.timeIntervalSince(now)))
        }
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        if phase == .exceeded { return 1 }
        let remaining = Double(remainingSeconds())
        let elapsed = totalDuration - remaining
        return min(1, max(0, elapsed / totalDuration))
    }
}
