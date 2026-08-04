//
//  TimerLiveActivityIntentPerformer.swift
//  RecipeScalerNative
//
//  Spec 030 Phase A (US-A1): Live Activity Pause/Resume intents update
//  ActivityKit + TimerSnapshotStore + WidgetCenter immediately, then still
//  enqueue TimerLiveActivityActionQueue for TimerManager drain.
//

import ActivityKit
import Foundation
import OSLog
import RecipeScalerCore
import WidgetKit

/// Injectable seams so Phase A logic is unit-testable without ActivityKit / WidgetCenter.
struct TimerLiveActivityIntentDependencies: Sendable {
    var loadActivity: @Sendable (String) -> (
        attributes: RecipeTimerActivityAttributes,
        state: RecipeTimerActivityAttributes.ContentState
    )?
    var updateActivity: @Sendable (
        String,
        RecipeTimerActivityAttributes.ContentState,
        Date?
    ) async -> Bool
    var applySnapshot: @Sendable (TimerSnapshot) -> Void
    var markPendingLocal: @Sendable () -> Void
    var reloadWidget: @Sendable () -> Void
    var enqueue: @Sendable (TimerLiveActivityAction, String) -> Void

    static let production = TimerLiveActivityIntentDependencies(
        loadActivity: { timerId in
            guard let activity = Activity<RecipeTimerActivityAttributes>.activities
                .first(where: { $0.attributes.timerId == timerId })
            else { return nil }
            return (activity.attributes, activity.content.state)
        },
        updateActivity: { timerId, state, staleDate in
            guard let activity = Activity<RecipeTimerActivityAttributes>.activities
                .first(where: { $0.attributes.timerId == timerId })
            else { return false }
            await activity.update(
                ActivityContent(state: state, staleDate: staleDate),
                alertConfiguration: nil
            )
            return true
        },
        applySnapshot: { snapshot in
            TimerSnapshotDocumentPatcher.applyAndSave(snapshot: snapshot)
        },
        markPendingLocal: {
            TimerSnapshotStore.markPendingLocalMutation()
        },
        reloadWidget: {
            WidgetCenter.shared.reloadTimelines(ofKind: TimerWidgetKind.id)
        },
        enqueue: { action, timerId in
            TimerLiveActivityActionQueue.enqueue(action: action, timerId: timerId)
        }
    )
}

enum TimerLiveActivityIntentPerformer {
    private static let log = Logger(
        subsystem: "com.recipescaler.native",
        category: "timer"
    )

    static func performPause(
        timerId: String,
        now: Date = Date(),
        dependencies: TimerLiveActivityIntentDependencies = .production
    ) async {
        guard !timerId.isEmpty else {
            log.error("live_activity_intent_pause_empty_timer_id")
            return
        }

        if let loaded = dependencies.loadActivity(timerId) {
            // Match TimerManager.pauseTimer: reject overdue (remaining < 0).
            let remaining = loaded.state.remainingSeconds(now: now)
            guard remaining >= 0 else {
                log.error("live_activity_intent_pause_rejected_overdue timerId=\(timerId, privacy: .public)")
                return
            }
            if loaded.state.phase == .paused {
                log.error("live_activity_intent_pause_already_paused timerId=\(timerId, privacy: .public)")
                return
            }

            let contentState = RecipeTimerActivityAttributes.ContentState(
                phase: .paused,
                endDate: nil,
                pausedRemainingSeconds: remaining,
                startedAt: loaded.state.startedAt,
                totalDuration: loaded.state.totalDuration,
                recipeName: loaded.state.recipeName,
                recipeThumbnailName: loaded.state.recipeThumbnailName,
                syncedAt: now
            )
            let updated = await dependencies.updateActivity(timerId, contentState, nil)
            if !updated {
                log.error("live_activity_intent_pause_activity_update_failed timerId=\(timerId, privacy: .public)")
            }

            let snapshot = TimerSnapshot(
                id: timerId,
                name: loaded.attributes.timerName,
                recipeId: loaded.attributes.recipeId,
                recipeName: loaded.state.recipeName,
                endDate: nil,
                pausedRemainingSeconds: remaining,
                phase: .paused,
                totalDurationSeconds: loaded.state.totalDuration
            )
            dependencies.markPendingLocal()
            dependencies.applySnapshot(snapshot)
            dependencies.reloadWidget()
            dependencies.enqueue(.pause, timerId)
            return
        }

        if let patched = Self.patchExistingSnapshot(
            timerId: timerId,
            action: .pause,
            now: now,
            markPendingLocal: dependencies.markPendingLocal,
            applySnapshot: dependencies.applySnapshot
        ) {
            _ = patched
            dependencies.reloadWidget()
            dependencies.enqueue(.pause, timerId)
            log.error("live_activity_intent_pause_no_activity_used_snapshot timerId=\(timerId, privacy: .public)")
            return
        }

        log.error("live_activity_intent_pause_no_activity_or_snapshot timerId=\(timerId, privacy: .public)")
    }

    static func performResume(
        timerId: String,
        now: Date = Date(),
        dependencies: TimerLiveActivityIntentDependencies = .production
    ) async {
        guard !timerId.isEmpty else {
            log.error("live_activity_intent_resume_empty_timer_id")
            return
        }

        if let loaded = dependencies.loadActivity(timerId) {
            // Match TimerManager.resumeTimer: require remaining > 0.
            let remaining = loaded.state.pausedRemainingSeconds
            guard remaining > 0 else {
                log.error("live_activity_intent_resume_rejected_nonpositive timerId=\(timerId, privacy: .public)")
                return
            }
            guard loaded.state.phase == .paused else {
                log.error("live_activity_intent_resume_not_paused timerId=\(timerId, privacy: .public)")
                return
            }

            let endDate = now.addingTimeInterval(TimeInterval(remaining))
            let stale: Date? = {
                var nextRefresh = endDate
                let total = loaded.state.totalDuration
                if total > 0 {
                    let soonThreshold = endDate.addingTimeInterval(-total / 10)
                    if soonThreshold > now {
                        nextRefresh = min(nextRefresh, soonThreshold)
                    }
                }
                return nextRefresh > now ? nextRefresh : nil
            }()

            let contentState = RecipeTimerActivityAttributes.ContentState(
                phase: .running,
                endDate: endDate,
                pausedRemainingSeconds: remaining,
                startedAt: loaded.state.startedAt,
                totalDuration: loaded.state.totalDuration,
                recipeName: loaded.state.recipeName,
                recipeThumbnailName: loaded.state.recipeThumbnailName,
                syncedAt: now
            )
            let updated = await dependencies.updateActivity(timerId, contentState, stale)
            if !updated {
                log.error("live_activity_intent_resume_activity_update_failed timerId=\(timerId, privacy: .public)")
            }

            let snapshot = TimerSnapshot(
                id: timerId,
                name: loaded.attributes.timerName,
                recipeId: loaded.attributes.recipeId,
                recipeName: loaded.state.recipeName,
                endDate: endDate,
                pausedRemainingSeconds: nil,
                phase: .running,
                totalDurationSeconds: loaded.state.totalDuration
            )
            dependencies.markPendingLocal()
            dependencies.applySnapshot(snapshot)
            dependencies.reloadWidget()
            dependencies.enqueue(.resume, timerId)
            return
        }

        if let patched = Self.patchExistingSnapshot(
            timerId: timerId,
            action: .resume,
            now: now,
            markPendingLocal: dependencies.markPendingLocal,
            applySnapshot: dependencies.applySnapshot
        ) {
            _ = patched
            dependencies.reloadWidget()
            dependencies.enqueue(.resume, timerId)
            log.error("live_activity_intent_resume_no_activity_used_snapshot timerId=\(timerId, privacy: .public)")
            return
        }

        log.error("live_activity_intent_resume_no_activity_or_snapshot timerId=\(timerId, privacy: .public)")
    }

    /// Fallback when ActivityKit has no matching activity but App Group already has the timer.
    /// Returns nil when guards reject (same rules as ActivityKit path).
    @discardableResult
    private static func patchExistingSnapshot(
        timerId: String,
        action: TimerLiveActivityAction,
        now: Date,
        markPendingLocal: @Sendable () -> Void,
        applySnapshot: @Sendable (TimerSnapshot) -> Void
    ) -> TimerSnapshot? {
        let doc = TimerSnapshotStore.load()
        guard let existing = doc.timers.first(where: { $0.id == timerId }) else {
            return nil
        }

        let patched: TimerSnapshot
        switch action {
        case .pause:
            let remaining = existing.remainingSeconds(now: now)
            guard remaining >= 0 else { return nil }
            guard existing.phase != .paused else { return nil }
            patched = TimerSnapshot(
                id: existing.id,
                name: existing.name,
                recipeId: existing.recipeId,
                recipeName: existing.recipeName,
                endDate: nil,
                pausedRemainingSeconds: remaining,
                phase: .paused,
                totalDurationSeconds: existing.totalDurationSeconds
            )
        case .resume:
            let remaining = existing.pausedRemainingSeconds ?? 0
            guard remaining > 0 else { return nil }
            guard existing.phase == .paused else { return nil }
            let endDate = now.addingTimeInterval(TimeInterval(remaining))
            patched = TimerSnapshot(
                id: existing.id,
                name: existing.name,
                recipeId: existing.recipeId,
                recipeName: existing.recipeName,
                endDate: endDate,
                pausedRemainingSeconds: nil,
                phase: .running,
                totalDurationSeconds: existing.totalDurationSeconds
            )
        }
        // Set the pending-local gate BEFORE writing the snapshot so a Provider
        // reload arriving in the micro-window between snapshot write and gate
        // set cannot fetch stale server state over the optimistic patch.
        markPendingLocal()
        applySnapshot(patched)
        return patched
    }
}
