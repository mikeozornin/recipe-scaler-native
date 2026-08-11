//
//  TimerListViewModel.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — bridges WatchTimerService (data) with TimerListView (UI).
//  Owns the navigation between List / Empty / Error / NotAuthorized states.
//  Detects foreground timer expiration and fires the agreed haptic pattern.
//
//  Spec 062 — drives WatchExpiryNotificationScheduler on every refresh and
//  on pause/delete/logout; suppresses foreground haptic when the user toggles
//  the prefs OFF.
//

import Foundation
import RecipeScalerCore

@MainActor
final class TimerListViewModel: ObservableObject {
    @Published private(set) var state: WatchTimerService.LoadState = .idle

    private let service = WatchTimerService()
    private let scheduler = WatchExpiryNotificationScheduler()
    /// Foreground poll interval — watch has no WebSocket in v1.
    private static let refreshIntervalSeconds: UInt64 = 15
    /// Previously seen "expired" set; used so we fire the haptic only once
    /// per timer that crosses the boundary while the app is foreground.
    private var firedExpirations: Set<String> = []
    private var prefsObserver: NSObjectProtocol?

    init() {
        // Wire userId changes (login/logout from iPhone) → service state.
        WatchCredentialsBridge.shared.onUserIdChange = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard WatchCredentialsStore.userId != nil else {
                    self.service.clear()
                    self.state = .notAuthorized
                    self.firedExpirations.removeAll()
                    await self.scheduler.cancelAll()
                    return
                }
                await self.refresh()
            }
        }
        WatchCredentialsBridge.shared.onTimersChanged = { [weak self] in
            Task { @MainActor in
                guard WatchCredentialsStore.userId != nil else { return }
                await self?.refresh()
            }
        }
        prefsObserver = NotificationCenter.default.addObserver(
            forName: WatchExpiryNotificationsPrefs.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // On toggle OFF — purge scheduled; on toggle ON — re-reconcile.
                if case let .loaded(timers) = self.state {
                    await self.scheduler.reconcile(timers: timers, now: Date())
                } else {
                    await self.scheduler.cancelAll()
                }
            }
        }
    }

    deinit {
        if let prefsObserver {
            NotificationCenter.default.removeObserver(prefsObserver)
        }
    }

    /// Initial load on app launch / wake. Safe to call repeatedly.
    func bootstrap() async {
        if WatchCredentialsStore.userId == nil {
            state = .notAuthorized
            return
        }
        await scheduler.requestAuthorizationIfNeeded()
        await refresh()
    }

    func refresh() async {
        await service.refresh()
        // Re-check credentials after the await — a purge may have landed
        // while the fetch was in flight (review M3).
        if WatchCredentialsStore.userId == nil {
            state = .notAuthorized
            await scheduler.cancelAll()
            return
        }
        state = service.state
        switch state {
        case .loaded(let timers):
            await scheduler.reconcile(timers: timers, now: Date())
        case .empty:
            // Remote delete of last timer — clear orphan pending (FR-004).
            await scheduler.cancelAll()
        default:
            break
        }
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
            // Resume → endDate may have changed; reconcile picks up new date.
            if case let .loaded(timers) = service.state {
                await scheduler.reconcile(timers: timers, now: Date())
            }
        } else {
            await scheduler.cancel(timerId: timer.id)
            await service.pause(timerId: timer.id, remaining: timer.remainingSeconds(now: Date()))
        }
        state = service.state
    }

    func delete(_ timer: WatchTimer) async {
        service.optimisticRemove(timerId: timer.id)
        state = service.state
        WatchHaptics.success()
        await scheduler.cancel(timerId: timer.id)
        await service.delete(timerId: timer.id)
        state = service.state
    }

    /// Scan the current list for timers that have crossed the expiry
    /// boundary since the last check and fire `WatchHaptics.timerExpired()`.
    /// Foreground-only — background expiration is handled by locally
    /// scheduled UNNotificationRequest (spec 062).
    private func checkForExpirations() {
        guard WatchExpiryNotificationsPrefs.isEnabled else { return }
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
