//
//  TimerWidgetProvider.swift
//  HomeWidgetExtension
//
//  Spec 030 — Timeline provider for `TimerWidget`.
//  Phase B3 + review fixes: network only when snapshot is stale and no
//  pending-local Intent mutation; getSnapshot is App Group only; single-flight.
//

import WidgetKit
import RecipeScalerCore

/// Coalesces overlapping Provider network refreshes (review finding #5).
private actor TimerWidgetNetworkRefreshGate {
    static let shared = TimerWidgetNetworkRefreshGate()
    private var inFlight: Task<Bool, Never>?

    func run(_ body: @escaping @Sendable () async -> Bool) async -> Bool {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await body() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}

/// Timeline provider for `TimerWidget`.
///
/// Reads `TimerSnapshotStore.load()` from the App Group on every reload.
/// Reloads are triggered by `TimerManager` (debounced 200ms after each mutation),
/// scenePhase transitions, and silent wake (B4). Network refresh is gated by
/// pending-local + TTL so host 1 Hz `reloadTimelines` stays local-only.
struct TimerWidgetProvider: TimelineProvider {
    /// Hard ceiling for extension network work (review #5).
    private static let networkTimeoutNanoseconds: UInt64 = 8_000_000_000

    func placeholder(in context: Context) -> TimerWidgetEntry {
        TimerWidgetEntry.placeholderSmall()
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerWidgetEntry) -> Void) {
        // Review #6 — snapshot must stay fast; App Group only.
        let document = TimerSnapshotStore.load()
        completion(TimerWidgetEntry(date: Date(), timers: document.timers))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerWidgetEntry>) -> Void) {
        // Build the timeline from the cached App Group snapshot first so iOS
        // gets a fast answer; the widget extension is not held alive by a
        // network round-trip. Code review 2026-08-05, finding #4.
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
        } else {
            let entry = TimerWidgetEntry(date: now, timers: timers)
            let nextReload = Self.nextReloadDate(for: timers, now: now)
            completion(Timeline(entries: [entry], policy: .after(nextReload)))
        }

        // Fire-and-forget refresh: if the fetch produces a different snapshot,
        // ask WidgetCenter for another reload so the new data renders. The
        // TimelineProvider contract allows `WidgetCenter.reloadTimelines` from
        // any process.
        Task {
            let didChange = await Self.refreshFromNetworkIfPossible()
            if didChange {
                WidgetCenter.shared.reloadTimelines(ofKind: TimerWidgetKind.id)
            }
        }
    }

    // MARK: - Network refresh (Phase B3 + review #1/#3/#4/#5)

    /// Fetch active timers when authenticated, snapshot stale, and no pending local.
    /// Never clears the snapshot on error.
    ///
    /// Returns `true` if the App Group snapshot was overwritten with new server
    /// data, so the caller can decide whether to call
    /// `WidgetCenter.shared.reloadTimelines(ofKind:)`. Code review 2026-08-05,
    /// finding #4 — `getTimeline` no longer blocks on this; it runs after the
    /// cached timeline has already been delivered.
    static func refreshFromNetworkIfPossible() async -> Bool {
        await TimerWidgetNetworkRefreshGate.shared.run {
            await Self.performNetworkRefreshWithTimeout()
        }
    }

    private static func performNetworkRefreshWithTimeout() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await Self.performNetworkRefresh()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: networkTimeoutNanoseconds)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private static func performNetworkRefresh() async -> Bool {
        let now = Date()
        let existing = TimerSnapshotStore.load()
        let pending = TimerSnapshotStore.hasPendingLocalMutation(now: now)

        guard TimerWidgetNetworkRefresh.shouldFetch(
            existing: existing,
            hasPendingLocal: pending,
            now: now
        ) else {
            return false
        }

        let bearer = SharedAuthStore.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bearer, !bearer.isEmpty else { return false }

        APIClient.shared.configure(authToken: bearer)
        if let userId = SharedAuthStore.userId, !userId.isEmpty {
            APIClient.shared.configure(userId: userId)
        }

        // Re-check pending after await gaps — Intent may have written meanwhile.
        let pendingBeforeApply = TimerSnapshotStore.hasPendingLocalMutation(now: Date())
        if pendingBeforeApply { return false }

        let fetchResult: Result<[ServerActiveTimer], Error>
        do {
            let response: ActiveTimersResponse = try await APIClient.shared.performDecodable(
                path: "/api/v1/timers/active"
            )
            if response.success, let timers = response.data?.timers {
                fetchResult = .success(timers)
            } else {
                fetchResult = .failure(APIError.invalidResponse)
            }
        } catch {
            fetchResult = .failure(error)
        }

        let applyNow = Date()
        switch TimerWidgetNetworkRefresh.apply(
            bearer: bearer,
            existing: existing,
            fetchResult: fetchResult,
            hasPendingLocal: TimerSnapshotStore.hasPendingLocalMutation(now: applyNow),
            now: applyNow
        ) {
        case .updated(let document):
            TimerSnapshotStore.save(document)
            return true
        case .keptExisting, .skippedNoAuth, .skippedPendingLocal:
            return false
        }
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
