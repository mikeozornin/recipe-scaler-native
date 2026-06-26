//
//  TimerOrdering.swift
//  RecipeScalerCore
//
//  Parity with `TimerUtils.sortTimers` on iPhone / web `timer-utils.ts`:
//  running timers first, then ascending remaining (soonest to finish on top).
//

import Foundation

public enum TimerOrdering {
    /// Sort active timers: running before paused, then by ascending remaining seconds.
    public static func sortActive<T>(
        _ timers: [T],
        now: Date = Date(),
        isPaused: (T) -> Bool,
        remainingSeconds: (T, Date) -> Int
    ) -> [T] {
        timers.sorted { lhs, rhs in
            let lhsPaused = isPaused(lhs)
            let rhsPaused = isPaused(rhs)
            if lhsPaused != rhsPaused { return !lhsPaused && rhsPaused }
            return remainingSeconds(lhs, now) < remainingSeconds(rhs, now)
        }
    }
}
