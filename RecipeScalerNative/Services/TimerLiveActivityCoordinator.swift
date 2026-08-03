//
//  TimerLiveActivityCoordinator.swift
//  RecipeScalerNative
//

import ActivityKit
import Foundation
import os
import UIKit

/// Why a Live Activity sync was requested (spec 058).
///
/// Background skip of local `.running` updates protects APNs-applied pause
/// (web/Watch) from stale in-memory `running`. That skip must **not** apply to
/// Lock Screen / App Intent / in-app controls — the source device is excluded
/// from APNs fan-out (R7 / US5), so self-resume would otherwise leave the card
/// stuck on paused.
enum LiveActivitySyncPolicy: Equatable, Sendable {
    /// Explicit local mutation: start, pause, resume, addTime, LA button, etc.
    case userAction
    /// Periodic progress / overdue ticks while the app is in memory.
    case progress
    /// Snapshot reconcile after server load / collection sync.
    case reconcile
}

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

    private static let Standalone = TimerLiveActivityCoordinator(
        pushRegistrar: LiveActivityPushRegistrar()
    )
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

    private let pushRegistrar: LiveActivityPushRegistering
    private var activityByTimerId: [String: Activity<RecipeTimerActivityAttributes>] = [:]
    private var failureTimestamps: [String: Date] = [:]
    private var activityUpdatesTask: Task<Void, Never>?
    /// Spec 058 — one task per live activity observing `pushTokenUpdates`.
    private var pushTokenTasks: [String: Task<Void, Never>] = [:]
    /// Bumped on every `stopObservingPushToken` so in-flight `register` can detect invalidation.
    private var pushTokenEpoch: [String: UInt64] = [:]
    /// After a failed register, wait before allowing `sync` to resubscribe (avoids 3s spin).
    private var pushTokenRetryAfter: [String: Date] = [:]
    /// Activities created this process with `pushType: .token` — skip legacy migration.
    private var createdWithPushTypeToken: Set<String> = []
    /// TimerIds that received at least one `pushTokenUpdates` emission this observation.
    private var pushTokenEmissionReceived: Set<String> = []
    /// One-shot migration: end restored activities that never emit a push token.
    private var legacyMigrationTasks: [String: Task<Void, Never>] = [:]

    /// How long to wait for a push-token emission before treating a restored
    /// activity as pre-058 (`pushType: nil`) and recreating it.
    private static let legacyPushMigrationTimeout: Duration = .seconds(8)
    /// Backoff after a failed token POST before the next `sync` may resubscribe.
    private static let pushRegisterRetryBackoff: TimeInterval = 30

    init(pushRegistrar: LiveActivityPushRegistering) {
        self.pushRegistrar = pushRegistrar
        startObservingActivityUpdates()
    }

    deinit {
        activityUpdatesTask?.cancel()
        for task in pushTokenTasks.values {
            task.cancel()
        }
        for task in legacyMigrationTasks.values {
            task.cancel()
        }
    }

    func restoreFromSystem() {
        for activity in Activity<RecipeTimerActivityAttributes>.activities {
            let timerId = activity.attributes.timerId
            activityByTimerId[timerId] = activity
            // Restored activities may predate pushType: .token — observe + migrate if silent.
            startObservingPushToken(for: activity, timerId: timerId, scheduleLegacyMigration: true)
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
            await sync(timer: timer, policy: .reconcile)
        }

        for (timerId, activity) in activityByTimerId where !visibleTimerIds.contains(timerId) {
            await end(activity: activity, timerId: timerId)
        }

        for activity in Activity<RecipeTimerActivityAttributes>.activities
            where !visibleTimerIds.contains(activity.attributes.timerId) {
            await end(timerId: activity.attributes.timerId)
        }
    }

    /// Pure predicate for the background-`.running` skip (unit-tested).
    ///
    /// Skip only for progress/reconcile when the app is not active and an
    /// activity already exists — never for `.userAction` (Lock Screen resume).
    static func shouldSkipBackgroundRunningUpdate(
        phase: TimerActivityPhase,
        appIsActive: Bool,
        hasExistingActivity: Bool,
        policy: LiveActivitySyncPolicy
    ) -> Bool {
        phase == .running
            && !appIsActive
            && hasExistingActivity
            && policy != .userAction
    }

    func sync(timer: RecipeTimer, policy: LiveActivitySyncPolicy) async {
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

        let hasExisting = activityByTimerId[timer.id] != nil
            || Activity<RecipeTimerActivityAttributes>.activities.contains(where: {
                $0.attributes.timerId == timer.id
            })
        // Spec 058: progress/reconcile must not overwrite APNs pause with stale
        // local `running` while backgrounded. User actions (Lock Screen resume)
        // always apply — source device is excluded from APNs (R7).
        if Self.shouldSkipBackgroundRunningUpdate(
            phase: contentState.phase,
            appIsActive: UIApplication.shared.applicationState == .active,
            hasExistingActivity: hasExisting,
            policy: policy
        ) {
            if let activity = activityByTimerId[timer.id]
                ?? Activity<RecipeTimerActivityAttributes>.activities.first(where: {
                    $0.attributes.timerId == timer.id
                }) {
                activityByTimerId[timer.id] = activity
                let needsMigration = !createdWithPushTypeToken.contains(timer.id)
                startObservingPushToken(
                    for: activity,
                    timerId: timer.id,
                    scheduleLegacyMigration: needsMigration
                )
            }
            return
        }

        if let activity = activityByTimerId[timer.id] {
            await activity.update(
                ActivityContent(
                    state: contentState,
                    staleDate: staleDate(for: timer, contentState: contentState)
                ),
                alertConfiguration: nil
            )
            let needsMigration = !createdWithPushTypeToken.contains(timer.id)
            startObservingPushToken(
                for: activity,
                timerId: timer.id,
                scheduleLegacyMigration: needsMigration
            )
            return
        }

        if let existing = Activity<RecipeTimerActivityAttributes>.activities
            .first(where: { $0.attributes.timerId == timer.id }) {
            activityByTimerId[timer.id] = existing
            let needsMigration = !createdWithPushTypeToken.contains(timer.id)
            startObservingPushToken(
                for: existing,
                timerId: timer.id,
                scheduleLegacyMigration: needsMigration
            )
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
            // Spec 058: `.token` so ActivityKit issues a push token for
            // cross-device Lock Screen updates when the app is backgrounded.
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: contentState,
                    staleDate: staleDate(for: timer, contentState: contentState)
                ),
                pushType: .token
            )
            activityByTimerId[timer.id] = activity
            // A successful request invalidates any stale negative-cache entry.
            failureTimestamps.removeValue(forKey: timer.id)
            createdWithPushTypeToken.insert(timer.id)
            startObservingPushToken(
                for: activity,
                timerId: timer.id,
                scheduleLegacyMigration: false
            )
            AppLog.info(.timer, "Started Live Activity for timer \(timer.id)")
        } catch {
            recordFailure(for: timer.id,
                          reason: "Activity.request failed: \(error.localizedDescription)")
        }
    }

    func end(timerId: String) async {
        failureTimestamps.removeValue(forKey: timerId)
        createdWithPushTypeToken.remove(timerId)
        stopObservingPushToken(timerId: timerId)
        await pushRegistrar.unregister(timerId: timerId)

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
            let timerId = activity.attributes.timerId
            createdWithPushTypeToken.remove(timerId)
            stopObservingPushToken(timerId: timerId)
            await pushRegistrar.unregister(timerId: timerId)
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Spec 058: end activities + wipe cached push-token keys. Call from every
    /// logout / session-wipe path so partial `endAll` cannot leave prior-user
    /// `liveActivityPushToken.*` entries (mirrors `FeatureAdoptionStore.clearForLogout`).
    func clearForLogout() async {
        await endAll()
        pushRegistrar.clearAllCachedTokens()
    }

    private func end(activity: Activity<RecipeTimerActivityAttributes>, timerId: String) async {
        activityByTimerId.removeValue(forKey: timerId)
        failureTimestamps.removeValue(forKey: timerId)
        createdWithPushTypeToken.remove(timerId)
        stopObservingPushToken(timerId: timerId)
        await pushRegistrar.unregister(timerId: timerId)
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: - ActivityKit push token (spec 058)

    private func startObservingPushToken(
        for activity: Activity<RecipeTimerActivityAttributes>,
        timerId: String,
        scheduleLegacyMigration: Bool
    ) {
        if let until = pushTokenRetryAfter[timerId], until > Date() {
            return
        }
        guard pushTokenTasks[timerId] == nil else { return }

        pushTokenTasks[timerId] = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.pushTokenEmissionReceived.insert(timerId)
                self.legacyMigrationTasks.removeValue(forKey: timerId)?.cancel()

                let epochAtStart = self.pushTokenEpoch[timerId] ?? 0
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                let ok = await self.pushRegistrar.register(timerId: timerId, tokenHex: hex)

                let epochNow = self.pushTokenEpoch[timerId] ?? 0
                if Task.isCancelled || epochNow != epochAtStart {
                    // Invalidated during the network call — undo a late success.
                    if ok {
                        await self.pushRegistrar.unregister(timerId: timerId)
                    }
                    return
                }

                if !ok {
                    // Clear the observer so a later sync can resubscribe after backoff.
                    self.pushTokenRetryAfter[timerId] = Date().addingTimeInterval(
                        Self.pushRegisterRetryBackoff
                    )
                    self.stopObservingPushToken(timerId: timerId)
                    return
                }

                self.pushTokenRetryAfter.removeValue(forKey: timerId)
            }
        }

        if scheduleLegacyMigration {
            scheduleLegacyPushMigrationIfNeeded(timerId: timerId)
        }
    }

    private func stopObservingPushToken(timerId: String) {
        pushTokenEpoch[timerId, default: 0] += 1
        pushTokenTasks.removeValue(forKey: timerId)?.cancel()
        legacyMigrationTasks.removeValue(forKey: timerId)?.cancel()
        pushTokenEmissionReceived.remove(timerId)
    }

    /// Pre-058 activities were created with `pushType: nil` and never emit tokens.
    /// After timeout with zero emissions, end them so the next `sync` recreates with `.token`.
    private func scheduleLegacyPushMigrationIfNeeded(timerId: String) {
        guard !createdWithPushTypeToken.contains(timerId) else { return }
        guard legacyMigrationTasks[timerId] == nil else { return }
        if pushRegistrar.hasCachedToken(timerId: timerId) { return }

        legacyMigrationTasks[timerId] = Task { [weak self] in
            try? await Task.sleep(for: Self.legacyPushMigrationTimeout)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard !self.pushTokenEmissionReceived.contains(timerId) else { return }
            guard self.activityByTimerId[timerId] != nil else { return }
            guard !self.createdWithPushTypeToken.contains(timerId) else { return }

            AppLog.notice(.timer, "live_activity_legacy_push_migration", data: [
                "timerId": timerId
            ])
            await self.end(timerId: timerId)
            // Next TimerManager sync recreates with pushType: .token.
        }
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
                createdWithPushTypeToken.remove(timerId)
                stopObservingPushToken(timerId: timerId)
                await pushRegistrar.unregister(timerId: timerId)
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
