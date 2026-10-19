//
//  TimerWidgetProvider.swift
//  HomeWidgetExtension
//
//  Spec 030 — Timeline provider for `TimerWidget`.
//  Phase B3 + review fixes: network only when snapshot is stale and no
//  pending-local Intent mutation; getSnapshot is App Group (empty in gallery);
//  single-flight.
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
        // Loading / gallery must not flash Figma stub timers (soon/orange).
        TimerWidgetEntry.empty
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerWidgetEntry) -> Void) {
        if context.isPreview {
            completion(TimerWidgetEntry.empty)
            return
        }
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

        let dates = TimerWidgetTimelineSchedule.entryDates(
            for: timers,
            now: now,
            secondGranularityWindow: WidgetTimerFormatting.liveCountdownThresholdSeconds
        )
        let entries = dates.map { TimerWidgetEntry(date: $0, timers: timers) }
        // Nothing ticking: the app reloads on every mutation, the fallback only
        // catches a missed one. Otherwise reload once the precomputed hour runs out.
        let policy: TimelineReloadPolicy = dates.count > 1
            ? .atEnd
            : .after(now.addingTimeInterval(Self.fallbackReloadInterval))
        completion(Timeline(entries: entries, policy: policy))

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

    // MARK: - Reload scheduling

    private static let fallbackReloadInterval: TimeInterval = 15 * 60
}
