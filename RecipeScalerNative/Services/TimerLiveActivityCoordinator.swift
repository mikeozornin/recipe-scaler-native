//
//  TimerLiveActivityCoordinator.swift
//  RecipeScalerNative
//

import ActivityKit
import Foundation
import os

@MainActor
final class TimerLiveActivityCoordinator {
    /// Shim: returns `AppContainer.shared.timerLiveActivityCoordinator` when
    /// the container is constructed, otherwise a stand-alone instance.
    static var shared: TimerLiveActivityCoordinator {
        if let container = AppContainer.shared {
            return container.timerLiveActivityCoordinator
        }
        return Standalone
    }

    private static let Standalone = TimerLiveActivityCoordinator()

    /// iOS imposes a hard cap on simultaneously running Live Activities per app
    /// (typically 5; ActivityKit surfaces it as
    /// `ActivityError.activityUnavailable("Maximum number of activities for target
    /// already exists")`). Used for budget management — when we hit the cap we
    /// evict the lowest-priority activity (if any) instead of failing.
    private static let systemActivityLimit = 5

    /// How long a `timerId` stays in `failureTimestamps` after an
    /// `Activity.request` failure. During this window further `sync(timer:)`
    /// calls short-circuit early instead of re-hitting ActivityKit on every
    /// tick (3–5 sec). Reset by `reconcile(with:)` and by `end(timerId:)`.
    private static let failureBackoff: TimeInterval = 30

    private var activityByTimerId: [String: Activity<RecipeTimerActivityAttributes>] = [:]
    private var failureTimestamps: [String: Date] = [:]
    private var activityUpdatesTask: Task<Void, Never>?

    init() {
        startObservingActivityUpdates()
    }

    deinit {
        activityUpdatesTask?.cancel()
    }

    func restoreFromSystem() {
        for activity in Activity<RecipeTimerActivityAttributes>.activities {
            activityByTimerId[activity.attributes.timerId] = activity
        }
    }

    func reconcile(with timers: [RecipeTimer]) async {
        // Clear negative cache: a reconcile represents a new "snapshot" of
        // intent and we should try again (e.g. user deleted an exceeded timer
        // and a slot may now be free).
        failureTimestamps.removeAll()

        restoreFromSystem()
        let visibleTimerIds = Set(timers.filter(shouldShowActivity(for:)).map(\.id))

        // Sort by priority (exceeded first, then soonest endTime) so the most
        // important timers claim the limited Live Activity slots first.
        let sortedToShow = timers
            .filter { shouldShowActivity(for: $0) }
            .sorted { lhs, rhs in
                priorityRank(for: lhs) < priorityRank(for: rhs)
            }

        for timer in sortedToShow {
            await sync(timer: timer)
        }

        for (timerId, activity) in activityByTimerId where !visibleTimerIds.contains(timerId) {
            await end(activity: activity, timerId: timerId)
        }

        for activity in Activity<RecipeTimerActivityAttributes>.activities
            where !visibleTimerIds.contains(activity.attributes.timerId) {
            await end(timerId: activity.attributes.timerId)
        }
    }

    func sync(timer: RecipeTimer) async {
        guard shouldShowActivity(for: timer) else {
            await end(timerId: timer.id)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            AppLog.notice(.timer, "Live Activities disabled (system or per-app Settings)")
            return
        }

        // Negative cache: skip if we recently failed to create an activity for
        // this timerId. The failure was almost certainly "limit reached" and
        // retrying on every 3–5s tick wastes ActivityKit calls.
        if let stamp = failureTimestamps[timer.id],
           Date().timeIntervalSince(stamp) < Self.failureBackoff {
            return
        }

        let metadata = await TimerLiveActivityMetadataProvider.metadata(for: timer.recipeId)
        let contentState = makeContentState(for: timer, metadata: metadata)

        if let activity = activityByTimerId[timer.id] {
            await activity.update(
                ActivityContent(
                    state: contentState,
                    staleDate: staleDate(for: timer, contentState: contentState)
                ),
                alertConfiguration: nil
            )
            return
        }

        if let existing = Activity<RecipeTimerActivityAttributes>.activities
            .first(where: { $0.attributes.timerId == timer.id }) {
            activityByTimerId[timer.id] = existing
            await existing.update(
                ActivityContent(
                    state: contentState,
                    staleDate: staleDate(for: timer, contentState: contentState)
                ),
                alertConfiguration: nil
            )
            return
        }

        // Budget management: before requesting a brand-new activity, check
        // whether the system cap is reached. If so, try to evict a strictly
        // lower-priority activity. If nothing can be evicted, skip this
        // request and record the failure so we don't retry every tick.
        let currentCount = Activity<RecipeTimerActivityAttributes>.activities.count
        if currentCount >= Self.systemActivityLimit {
            guard let victim = lowestPriorityEvictableActivity(preference: timer) else {
                recordFailure(for: timer.id,
                              reason: "Live Activity limit reached, no eviction candidate")
                return
            }
            failureTimestamps.removeValue(forKey: victim.attributes.timerId)
            await end(activity: victim, timerId: victim.attributes.timerId)
        }

        let attributes = makeAttributes(timer: timer)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: contentState,
                    staleDate: staleDate(for: timer, contentState: contentState)
                ),
                pushType: nil
            )
            activityByTimerId[timer.id] = activity
            // A successful request invalidates any stale negative-cache entry.
            failureTimestamps.removeValue(forKey: timer.id)
            AppLog.info(.timer, "Started Live Activity for timer \(timer.id)")
        } catch {
            recordFailure(for: timer.id,
                          reason: "Activity.request failed: \(error.localizedDescription)")
        }
    }

    func end(timerId: String) async {
        failureTimestamps.removeValue(forKey: timerId)

        if let activity = activityByTimerId.removeValue(forKey: timerId) {
            await activity.end(nil, dismissalPolicy: .immediate)
            return
        }

        if let activity = Activity<RecipeTimerActivityAttributes>.activities
            .first(where: { $0.attributes.timerId == timerId }) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Spec 055 Phase R: end every currently-installed Live Activity for this
    /// app. Used during account-invalidation wipe so the Lock Screen does not
    /// keep advertising a deleted user's recipe timers. Best-effort — swallows
    /// per-activity errors so one bad activity doesn't block the rest.
    func endAll() async {
        for timerId in Array(activityByTimerId.keys) {
            await end(timerId: timerId)
        }
        for activity in Activity<RecipeTimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func end(activity: Activity<RecipeTimerActivityAttributes>, timerId: String) async {
        activityByTimerId.removeValue(forKey: timerId)
        failureTimestamps.removeValue(forKey: timerId)
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func shouldShowActivity(for timer: RecipeTimer) -> Bool {
        timer.isRunning || timer.isPaused
    }

    // MARK: - Priority / budget

    /// A sort key describing how strongly a timer "deserves" a Live Activity slot.
    ///
    /// Lower tuple = higher priority.
    ///   1. Exceeded timers (rang but not dismissed) — most important to surface.
    ///      Within the group, oldest-endTime first (longest overdue).
    ///   2. Running timers — soonest endTime first (about to ring).
    ///   3. Paused timers — soonest endTime first (most relevant).
    ///
    /// `Date.distantFuture` is used for nil endTime so that timers without an
    /// endTime (shouldn't happen for running/exceeded, but defensive) sort
    /// last within their group.
    private func priorityRank(for timer: RecipeTimer) -> (Int, Date) {
        let remaining = timer.endTime.map { $0.timeIntervalSinceNow } ?? .infinity
        let isExceeded = timer.hasCompleted
            && (timer.endTime.map { $0 <= Date() } ?? false)
            || (timer.isRunning && remaining <= 0)

        let group: Int
        if isExceeded {
            group = 0
        } else if timer.isRunning {
            group = 1
        } else {
            group = 2
        }
        return (group, timer.endTime ?? .distantFuture)
    }

    /// Returns the lowest-priority currently-installed activity whose owning
    /// timer is strictly lower-priority than the `preference` timer. If every
    /// installed activity is at least as important as `preference`, returns nil
    /// (no eviction — we'd rather keep what's shown than churn).
    ///
    /// Resolves the victim's owning timer via the in-memory `timers` snapshot
    /// passed through `AppContainer.shared.timer.timers` so we have access to
    /// the full RecipeTimer (not just the Activity's attributes).
    private func lowestPriorityEvictableActivity(
        preference preferredTimer: RecipeTimer
    ) -> Activity<RecipeTimerActivityAttributes>? {
        let preferredRank = priorityRank(for: preferredTimer)
        let timersById = currentTimersById()

        var worstActivity: Activity<RecipeTimerActivityAttributes>?
        var worstRank: (Int, Date) = (Int.min, .distantPast)

        for activity in Activity<RecipeTimerActivityAttributes>.activities {
            let timerId = activity.attributes.timerId
            let rank: (Int, Date)
            if let timer = timersById[timerId] {
                rank = priorityRank(for: timer)
            } else {
                // Orphaned activity (timer no longer in memory). It is the
                // lowest-priority possible — evict it preferentially.
                rank = (Int.max, .distantFuture)
            }

            // Strictly lower priority than the candidate we'd like to install.
            let isWorseThanPreferred = rank.0 > preferredRank.0
                || (rank.0 == preferredRank.0 && rank.1 > preferredRank.1)
            guard isWorseThanPreferred else { continue }

            // Pick the worst of all worse-than-preferred candidates.
            let isWorseThanCurrent = rank.0 > worstRank.0
                || (rank.0 == worstRank.0 && rank.1 > worstRank.1)
            if isWorseThanCurrent {
                worstRank = rank
                worstActivity = activity
            }
        }

        return worstActivity
    }

    /// Pulls the current `TimerManager.timers` snapshot. Returns empty when the
    /// container or timer manager is unavailable (e.g. preview / test
    /// contexts), in which case eviction falls back to attribute-only matching.
    private func currentTimersById() -> [String: RecipeTimer] {
        guard let container = AppContainer.shared else {
            return [:]
        }
        var result: [String: RecipeTimer] = [:]
        for timer in container.timer.timers {
            result[timer.id] = timer
        }
        return result
    }

    private func recordFailure(for timerId: String, reason: String) {
        failureTimestamps[timerId] = Date()
        // `.notice` — this is an expected condition when the user has many
        // simultaneous timers, not a bug to investigate.
        AppLog.notice(.timer, "Skipping Live Activity for \(timerId): \(reason)")
    }

    // MARK: - ActivityKit updates observation

    /// Listens for system/user-initiated activity terminations and removes
    /// them from `activityByTimerId`. Without this, a user-swiped Live
    /// Activity would leave a stale entry in the in-memory cache, and
    /// subsequent `sync(timer:)` calls would `update(...)` an already-ended
    /// activity (silently failing).
    private func startObservingActivityUpdates() {
        activityUpdatesTask?.cancel()
        activityUpdatesTask = Task { [weak self] in
            // `activityUpdates` is a main-actor-bound async sequence on iOS 16+.
            for await activity in Activity<RecipeTimerActivityAttributes>.activityUpdates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.handleActivityUpdate(activity)
            }
        }
    }

    private func handleActivityUpdate(
        _ activity: Activity<RecipeTimerActivityAttributes>
    ) async {
        let state = activity.activityState
        switch state {
        case .dismissed, .ended:
            let timerId = activity.attributes.timerId
            if activityByTimerId[timerId] === activity
                || activityByTimerId[timerId] == nil {
                activityByTimerId.removeValue(forKey: timerId)
            }
        default:
            break
        }
    }

    // MARK: - Content state

    private func makeAttributes(timer: RecipeTimer) -> RecipeTimerActivityAttributes {
        RecipeTimerActivityAttributes(
            timerId: timer.id,
            timerName: timer.name,
            recipeId: timer.recipeId
        )
    }

    private func makeContentState(
        for timer: RecipeTimer,
        metadata: TimerLiveActivityRecipeMetadata
    ) -> RecipeTimerActivityAttributes.ContentState {
        let remaining = TimerUtils.remainingSeconds(for: timer)
        let phase: TimerActivityPhase
        if remaining < 0 && timer.isRunning {
            phase = .exceeded
        } else if timer.isPaused {
            phase = .paused
        } else if timer.isRunning {
            phase = .running
        } else {
            phase = .paused
        }

        let startedAt = timer.startedAt ?? timer.createdAt

        return RecipeTimerActivityAttributes.ContentState(
            phase: phase,
            endDate: timer.endTime,
            pausedRemainingSeconds: Int(timer.remainingTime ?? timer.duration),
            startedAt: startedAt,
            totalDuration: timer.duration,
            recipeName: metadata.recipeName ?? timer.recipeDisplayName,
            recipeThumbnailName: metadata.thumbnailName,
            syncedAt: Date()
        )
    }

    private func staleDate(
        for timer: RecipeTimer,
        contentState: RecipeTimerActivityAttributes.ContentState
    ) -> Date? {
        if contentState.phase == .exceeded { return nil }
        if contentState.phase == .paused { return nil }
        guard let endTime = timer.endTime else { return nil }

        let now = Date()
        var nextRefresh = endTime
        if timer.duration > 0 {
            let soonThreshold = endTime.addingTimeInterval(-timer.duration / 10)
            if soonThreshold > now {
                nextRefresh = min(nextRefresh, soonThreshold)
            }
        }
        return nextRefresh > now ? nextRefresh : nil
    }
}
