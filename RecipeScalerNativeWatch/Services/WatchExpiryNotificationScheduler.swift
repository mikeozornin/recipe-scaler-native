//
//  WatchExpiryNotificationScheduler.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 062 — owns the `watch-timer-<id>-complete` namespace in
//  `UNUserNotificationCenter`. Plans a UNCalendarNotificationTrigger per
//  active non-paused timer; reconciles pending ↔ current timer list on every
//  refresh; cancels on pause/delete/logout; suppresses all activity when the
//  user toggles "Haptics при окончании" OFF.
//
//  Pure scheduling logic (identifier parsing, grace interval, diff) lives
//  in `WatchExpiryNotificationPlanner` (RecipeScalerCore) for testability.
//

import Foundation
import UserNotifications
import os
import RecipeScalerCore

actor WatchExpiryNotificationScheduler {

    private static let subsystem = "ru.recipescaler.RecipeScaler.watch"
    private static let category = "ExpiryScheduler"
    private let logger = Logger(subsystem: subsystem, category: category)

    private let center: UNUserNotificationCenter
    private var reconcileGeneration: UInt64 = 0

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Public API

    /// Ask the system for permission. Safe to call repeatedly; the system
    /// remembers a prior grant/denial.
    func requestAuthorizationIfNeeded() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            logger.info("requestAuthorization granted=\(granted)")
        } catch {
            logger.error("requestAuthorization failed: \(error.localizedDescription)")
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Bring pending notification set in sync with the current timer list.
    /// Single-flight by generation: a stale run that crossed an `await`
    /// while a newer `reconcile` / `cancel` started will silently abort.
    func reconcile(timers: [WatchTimer], now: Date) async {
        guard WatchExpiryNotificationsPrefs.isEnabled else {
            await cancelAll()
            return
        }

        reconcileGeneration &+= 1
        let myGeneration = reconcileGeneration

        let snapshots = timers.map { timer in
            WatchExpiryNotificationPlanner.TimerSnapshot(
                id: timer.id,
                endDate: timer.endDate,
                isPaused: timer.isPaused
            )
        }
        let keep = WatchExpiryNotificationPlanner.keepEndDates(for: snapshots, now: now)
        let add = WatchExpiryNotificationPlanner.addEndDates(for: snapshots, now: now)

        let pending = await fetchPendingEntries()
        guard myGeneration == reconcileGeneration else { return }

        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pending: pending,
            keepEndDates: keep,
            addEndDates: add
        )

        if !diff.remove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.remove)
        }

        for (timerId, endDate) in diff.add {
            guard myGeneration == reconcileGeneration else { return }
            let request = makeRequest(timerId: timerId, endDate: endDate)
            do {
                try await center.add(request)
            } catch {
                logger.error("add request failed timerId=\(timerId): \(error.localizedDescription)")
            }
        }
    }

    /// Cancel a single timer's pending notification. Idempotent.
    /// Invalidates in-flight reconcile so a stale run cannot re-add.
    func cancel(timerId: String) async {
        reconcileGeneration &+= 1
        center.removePendingNotificationRequests(
            withIdentifiers: [WatchExpiryNotificationPlanner.identifier(for: timerId)]
        )
    }

    /// Cancel every `watch-timer-*` pending request. Used on logout and when
    /// the user toggles the prefs OFF.
    /// Invalidates in-flight reconcile so a stale run cannot re-add.
    func cancelAll() async {
        reconcileGeneration &+= 1
        let pending = await fetchPendingEntries()
        let watchOwned = pending.map(\.identifier).filter { id in
            WatchExpiryNotificationPlanner.timerId(from: id) != nil
        }
        if !watchOwned.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: watchOwned)
            logger.info("cancelAll removed \(watchOwned.count) pending")
        }
    }

    // MARK: - Helpers

    private func fetchPendingEntries() async -> [WatchExpiryNotificationPlanner.PendingEntry] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let entries = requests.map { request in
                    let fireDate = (request.trigger as? UNCalendarNotificationTrigger)?
                        .nextTriggerDate()
                    return WatchExpiryNotificationPlanner.PendingEntry(
                        identifier: request.identifier,
                        fireDate: fireDate
                    )
                }
                continuation.resume(returning: entries)
            }
        }
    }

    private func makeRequest(timerId: String, endDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "watch.timer.notification.title",
            comment: ""
        )
        content.body = NSLocalizedString(
            "watch.timer.notification.body",
            comment: ""
        )
        // Sound intentionally nil — spec 062 decision.
        content.sound = nil
        content.userInfo = ["timerId": timerId]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: endDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: WatchExpiryNotificationPlanner.identifier(for: timerId),
            content: content,
            trigger: trigger
        )
    }
}
