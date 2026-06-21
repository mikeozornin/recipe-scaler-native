//
//  TimerWidgetProvider.swift
//  HomeWidgetExtension
//
//  Spec 030 — Timeline provider for `TimerWidget`.
//

import WidgetKit
import RecipeScalerCore

/// Timeline provider for `TimerWidget`.
///
/// Reads `TimerSnapshotStore.load()` from the App Group on every reload.
/// Reloads are triggered by `TimerManager` (debounced 200ms after each mutation)
/// and by scenePhase transitions in the host app.
struct TimerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerWidgetEntry {
        TimerWidgetEntry.placeholderSmall()
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerWidgetEntry) -> Void) {
        let document = TimerSnapshotStore.load()
        completion(TimerWidgetEntry(date: Date(), timers: document.timers))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerWidgetEntry>) -> Void) {
        let document = TimerSnapshotStore.load()
        let now = Date()
        let timers = document.timers

        if Self.needsSecondGranularity(timers, now: now) {
            let horizon = Self.secondGranularityHorizon(timers, now: now)
            let entries = (0..<horizon).map { offset in
                TimerWidgetEntry(
                    date: now.addingTimeInterval(TimeInterval(offset)),
                    timers: timers
                )
            }
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }

        let entry = TimerWidgetEntry(date: now, timers: timers)
        let nextReload = Self.nextReloadDate(for: timers, now: now)
        completion(Timeline(entries: [entry], policy: .after(nextReload)))
    }

    // MARK: - Reload scheduling (compact `Nm` / `Ns` labels)

    private static let fallbackReloadInterval: TimeInterval = 15 * 60

    /// Per-second entries for the last minute (`35s`) and sub-minute overdue (`-35s`).
    static func needsSecondGranularity(_ timers: [TimerSnapshot], now: Date) -> Bool {
        timers.contains { timer in
            guard timer.phase == .running || timer.phase == .exceeded else { return false }
            let remaining = timer.remainingSeconds(now: now)
            let magnitude = abs(remaining)
            return magnitude < WidgetTimerFormatting.liveCountdownThresholdSeconds
        }
    }

    static func secondGranularityHorizon(_ timers: [TimerSnapshot], now: Date) -> Int {
        let maxTicks = timers.compactMap { timer -> Int? in
            guard timer.phase == .running || timer.phase == .exceeded else { return nil }
            let remaining = timer.remainingSeconds(now: now)
            let magnitude = abs(remaining)
            guard magnitude < WidgetTimerFormatting.liveCountdownThresholdSeconds else {
                return nil
            }
            // At 0s keep ticking into overdue (`-1s`, `-2s`, …) for up to one minute.
            if magnitude == 0 {
                return WidgetTimerFormatting.liveCountdownThresholdSeconds
            }
            return magnitude
        }.max() ?? 0
        return min(max(maxTicks + 1, 1), WidgetTimerFormatting.liveCountdownThresholdSeconds)
    }

    /// Picks the soonest reload so compact `Nm` / `Ns` labels advance on minute/second boundaries.
    static func nextReloadDate(for timers: [TimerSnapshot], now: Date) -> Date {
        guard !timers.isEmpty else {
            return now.addingTimeInterval(fallbackReloadInterval)
        }

        var candidates: [Date] = []

        for timer in timers {
            let remaining = timer.remainingSeconds(now: now)
            switch timer.phase {
            case .running, .exceeded:
                if remaining >= WidgetTimerFormatting.liveCountdownThresholdSeconds
                    || remaining <= -WidgetTimerFormatting.liveCountdownThresholdSeconds {
                    if let minute = nextMinuteBoundary(after: now) {
                        candidates.append(minute)
                    }
                } else if remaining > 0 {
                    candidates.append(now.addingTimeInterval(1))
                    if let endDate = timer.endDate, endDate > now {
                        candidates.append(endDate)
                    }
                } else if remaining == 0 {
                    candidates.append(now.addingTimeInterval(1))
                } else if remaining < 0 {
                    candidates.append(now.addingTimeInterval(1))
                }
            case .paused:
                break
            }
        }

        return candidates.filter { $0 > now }.min()
            ?? now.addingTimeInterval(fallbackReloadInterval)
    }

    private static func nextMinuteBoundary(after date: Date) -> Date? {
        let calendar = Calendar.current
        guard let nextMinute = calendar.date(byAdding: .minute, value: 1, to: date) else {
            return nil
        }
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: nextMinute
        )
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components)
    }
}
