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
    private var inFlight: Task<Void, Never>?

    func run(_ body: @escaping @Sendable () async -> Void) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await body() }
        inFlight = task
        await task.value
        inFlight = nil
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
        Task {
            await Self.refreshFromNetworkIfPossible()
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
    }

    // MARK: - Network refresh (Phase B3 + review #1/#3/#4/#5)

    /// Fetch active timers when authenticated, snapshot stale, and no pending local.
    /// Never clears the snapshot on error.
    static func refreshFromNetworkIfPossible() async {
        await TimerWidgetNetworkRefreshGate.shared.run {
            await Self.performNetworkRefreshWithTimeout()
        }
    }

    private static func performNetworkRefreshWithTimeout() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await Self.performNetworkRefresh()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: networkTimeoutNanoseconds)
            }
            await group.next()
            group.cancelAll()
        }
    }

    private static func performNetworkRefresh() async {
        let now = Date()
        let existing = TimerSnapshotStore.load()
        let pending = TimerSnapshotStore.hasPendingLocalMutation(now: now)

        guard TimerWidgetNetworkRefresh.shouldFetch(
            existing: existing,
            hasPendingLocal: pending,
            now: now
        ) else {
            return
        }

        let bearer = SharedAuthStore.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bearer, !bearer.isEmpty else { return }

        APIClient.shared.configure(authToken: bearer)
        if let userId = SharedAuthStore.userId, !userId.isEmpty {
            APIClient.shared.configure(userId: userId)
        }

        // Re-check pending after await gaps — Intent may have written meanwhile.
        let pendingBeforeApply = TimerSnapshotStore.hasPendingLocalMutation(now: Date())
        if pendingBeforeApply { return }

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
            existing: TimerSnapshotStore.load(),
            fetchResult: fetchResult,
            hasPendingLocal: TimerSnapshotStore.hasPendingLocalMutation(now: applyNow),
            now: applyNow
        ) {
        case .updated(let document):
            TimerSnapshotStore.save(document)
        case .keptExisting, .skippedNoAuth, .skippedPendingLocal:
            break
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
