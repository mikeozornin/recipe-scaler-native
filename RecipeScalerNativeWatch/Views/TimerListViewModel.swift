//
//  TimerListViewModel.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — bridges WatchTimerService (data) with TimerListView (UI).
//  Owns the navigation between List / Empty / Error / NotAuthorized states.
//  Detects foreground timer expiration and fires the agreed haptic pattern.
//

import Foundation
import RecipeScalerCore

@MainActor
final class TimerListViewModel: ObservableObject {
    @Published private(set) var state: WatchTimerService.LoadState = .idle

    private let service = WatchTimerService()
    /// Foreground poll interval — watch has no WebSocket in v1.
    private static let refreshIntervalSeconds: UInt64 = 15
    /// Previously seen "expired" set; used so we fire the haptic only once
    /// per timer that crosses the boundary while the app is foreground.
    private var firedExpirations: Set<String> = []

    init() {
        // Wire userId changes (login/logout from iPhone) → service state.
        WatchCredentialsBridge.shared.onUserIdChange = { [weak self] _ in
            Task { @MainActor in
                guard WatchCredentialsStore.userId != nil else {
                    self?.service.clear()
                    self?.state = .notAuthorized
                    return
                }
                await self?.refresh()
            }
        }
        WatchCredentialsBridge.shared.onTimersChanged = { [weak self] in
            Task { @MainActor in
                guard WatchCredentialsStore.userId != nil else { return }
                await self?.refresh()
            }
        }
    }

    /// Initial load on app launch / wake. Safe to call repeatedly.
    func bootstrap() async {
        if WatchCredentialsStore.userId == nil {
            state = .notAuthorized
            return
        }
        await refresh()
    }

    func refresh() async {
        await service.refresh()
        // Re-check credentials after the await — a purge may have landed
        // while the fetch was in flight (review M3).
        if WatchCredentialsStore.userId == nil {
            state = .notAuthorized
            return
        }
        state = service.state
        checkForExpirations()
    }

    /// Poll `GET /active` while the list is on screen so iPhone/web timer
    /// changes reach the watch without WebSocket (v1).
    func foregroundRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.refreshIntervalSeconds * 1_000_000_000)
            guard WatchCredentialsStore.userId != nil else { continue }
            guard shouldPollForRemoteChanges else { continue }
            await refresh()
        }
    }

    private var shouldPollForRemoteChanges: Bool {
        switch state {
        case .loaded, .empty, .error:
            return true
        case .idle, .loading, .notAuthorized:
            return false
        }
    }

    func togglePause(_ timer: WatchTimer) async {
        service.optimisticToggle(timerId: timer.id)
        state = service.state
        WatchHaptics.click()
        if timer.isPaused {
            await service.resume(timerId: timer.id)
        } else {
            await service.pause(timerId: timer.id, remaining: timer.remainingSeconds(now: Date()))
        }
        state = service.state
    }

    func delete(_ timer: WatchTimer) async {
        service.optimisticRemove(timerId: timer.id)
        state = service.state
        WatchHaptics.success()
        await service.delete(timerId: timer.id)
        state = service.state
    }

    /// Scan the current list for timers that have crossed the expiry
    /// boundary since the last check and fire `WatchHaptics.timerExpired()`.
    /// Foreground-only — background expiration still needs push (v2).
    private func checkForExpirations() {
        guard case let .loaded(timers) = state else { return }
        let now = Date()
        var newExpirations: Set<String> = []
        for timer in timers where !timer.isPaused {
            guard let endDate = timer.endDate else { continue }
            if endDate <= now, !firedExpirations.contains(timer.id) {
                newExpirations.insert(timer.id)
            }
        }
        guard !newExpirations.isEmpty else { return }
        firedExpirations.formUnion(newExpirations)
        WatchHaptics.timerExpired()
    }
}
