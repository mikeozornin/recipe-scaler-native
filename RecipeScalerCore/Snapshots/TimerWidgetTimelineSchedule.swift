//
//  TimerWidgetTimelineSchedule.swift
//  RecipeScalerCore
//
//  Entry dates for `TimerWidgetProvider`. One timeline covers up to an hour of
//  label changes, so the widget advances on its own instead of asking WidgetKit
//  for a reload every minute: that burned the daily reload budget within an
//  hour and the countdown froze until the app was opened again.
//

import Foundation

public enum TimerWidgetTimelineSchedule {
    /// `now` followed by every second within `horizonSeconds` at which a ticking
    /// timer's compact label (`4m`, `35s`, `-2m`, `1,8h`) or accent changes.
    /// Returns `[now]` when nothing is ticking.
    public static func entryDates(
        for timers: [TimerSnapshot],
        now: Date,
        secondGranularityWindow: Int,
        horizonSeconds: Int = 3600,
        maxEntries: Int = 360
    ) -> [Date] {
        let ticking = timers.filter { $0.phase == .running || $0.phase == .exceeded }
        guard !ticking.isEmpty else { return [now] }

        var dates = [now]
        for offset in 1...horizonSeconds {
            guard dates.count < maxEntries else { break }
            let date = now.addingTimeInterval(TimeInterval(offset))
            if ticking.contains(where: { isBoundary($0, at: date, window: secondGranularityWindow) }) {
                dates.append(date)
            }
        }
        return dates
    }

    private static func isBoundary(_ timer: TimerSnapshot, at date: Date, window: Int) -> Bool {
        let remaining = timer.remainingSeconds(now: date)
        // Second labels around zero: `59s` … `0s` … `-59s`.
        if remaining < window, remaining >= -window { return true }
        // `2m` → `1m` (and hour tenths) flip when 119, 179, … seconds are left.
        if remaining > 0, (remaining + 1) % 60 == 0 { return true }
        // `-1m` → `-2m` flips at -120, -180, …
        if remaining < 0, remaining % 60 == 0 { return true }
        // `WidgetTimerAccent.soon` starts below a tenth of the duration.
        guard timer.totalDurationSeconds.isFinite else { return false }
        let soonThreshold = Int(timer.totalDurationSeconds) / 10
        return soonThreshold > 0 && remaining == soonThreshold - 1
    }
}
