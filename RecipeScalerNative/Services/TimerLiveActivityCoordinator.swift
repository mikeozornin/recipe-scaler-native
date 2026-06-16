//
//  TimerLiveActivityCoordinator.swift
//  RecipeScalerNative
//

import ActivityKit
import Foundation
import os

@MainActor
final class TimerLiveActivityCoordinator {
    static let shared = TimerLiveActivityCoordinator()


    private var activityByTimerId: [String: Activity<RecipeTimerActivityAttributes>] = [:]
    private var exceededDismissTasks: [String: Task<Void, Never>] = [:]

    private static let exceededDismissDelay: TimeInterval = 30 * 60

    private init() {}

    func restoreFromSystem() {
        for activity in Activity<RecipeTimerActivityAttributes>.activities {
            activityByTimerId[activity.attributes.timerId] = activity
        }
    }

    func reconcile(with timers: [RecipeTimer]) async {
        restoreFromSystem()
        let visibleTimerIds = Set(timers.filter(shouldShowActivity(for:)).map(\.id))

        for timer in timers where shouldShowActivity(for: timer) {
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
            handleExceededDismissSchedule(timerId: timer.id, state: contentState)
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
            handleExceededDismissSchedule(timerId: timer.id, state: contentState)
            return
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
            AppLog.info(.timer, "Started Live Activity for timer \(timer.id)")
            handleExceededDismissSchedule(timerId: timer.id, state: contentState)
        } catch {
            let message = "Activity.request failed for \(timer.id): \(error.localizedDescription)"
            AppLog.error(.timer, message)
        }
    }

    func end(timerId: String) async {
        exceededDismissTasks[timerId]?.cancel()
        exceededDismissTasks.removeValue(forKey: timerId)

        if let activity = activityByTimerId.removeValue(forKey: timerId) {
            await activity.end(nil, dismissalPolicy: .immediate)
            return
        }

        if let activity = Activity<RecipeTimerActivityAttributes>.activities
            .first(where: { $0.attributes.timerId == timerId }) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func end(activity: Activity<RecipeTimerActivityAttributes>, timerId: String) async {
        activityByTimerId.removeValue(forKey: timerId)
        exceededDismissTasks[timerId]?.cancel()
        exceededDismissTasks.removeValue(forKey: timerId)
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func shouldShowActivity(for timer: RecipeTimer) -> Bool {
        timer.isRunning || timer.isPaused
    }

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

    private func handleExceededDismissSchedule(
        timerId: String,
        state: RecipeTimerActivityAttributes.ContentState
    ) {
        if state.phase == .exceeded {
            guard exceededDismissTasks[timerId] == nil else { return }
            exceededDismissTasks[timerId] = Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.exceededDismissDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if let activity = activityByTimerId[timerId] {
                    await activity.end(nil, dismissalPolicy: .after(.now + 1))
                    activityByTimerId.removeValue(forKey: timerId)
                }
                exceededDismissTasks.removeValue(forKey: timerId)
            }
        } else {
            exceededDismissTasks[timerId]?.cancel()
            exceededDismissTasks.removeValue(forKey: timerId)
        }
    }
}
