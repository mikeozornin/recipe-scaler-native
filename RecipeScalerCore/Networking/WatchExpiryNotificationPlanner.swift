//
//  WatchExpiryNotificationPlanner.swift
//  RecipeScalerCore
//
//  Spec 062 — pure logic for watch expiry notification scheduling.
//  Extracted from `WatchExpiryNotificationScheduler` (watch target) so that
//  the diff/desired-set/identifier logic is unit-testable from
//  `RecipeScalerNativeTests` without importing watch-only dependencies
//  (WatchKit, etc.).
//
//  Reference:
//  specs/062-watch-timer-expiry-notify/data-model.md,
//  specs/062-watch-timer-expiry-notify/contracts/notification-identifiers.md.
//

import Foundation

/// Pure (no I/O) planner for `watch-timer-<id>-complete` notifications.
public enum WatchExpiryNotificationPlanner {

    public static let identifierPrefix = "watch-timer-"
    public static let identifierSuffix = "-complete"

    /// Don't *schedule new* notifications whose endDate is within this many
    /// seconds of "now" — covers cold-launch with already-expired timers
    /// (FR-007). Already-pending requests inside the grace window MUST be
    /// kept (data-model I5) — see `keepEndDates` vs `addEndDates`.
    public static let graceInterval: TimeInterval = 5

    /// Tolerance when comparing a pending trigger date to desired endDate.
    public static let endDateMatchTolerance: TimeInterval = 1

    /// Build the deterministic identifier for a given timerId.
    public static func identifier(for timerId: String) -> String {
        "\(identifierPrefix)\(timerId)\(identifierSuffix)"
    }

    /// Reverse-parse an identifier produced by `identifier(for:)`.
    /// Returns nil for identifiers outside our namespace.
    public static func timerId(from identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix),
              identifier.hasSuffix(identifierSuffix) else {
            return nil
        }
        let start = identifier.index(identifier.startIndex, offsetBy: identifierPrefix.count)
        let end = identifier.index(identifier.endIndex, offsetBy: -identifierSuffix.count)
        guard start < end else { return nil }
        return String(identifier[start..<end])
    }

    /// Inputs to scheduling decisions. Decoupled from `WatchTimer` (which
    /// lives in the watch target) so this can be tested from core tests.
    public struct TimerSnapshot: Equatable {
        public let id: String
        public let endDate: Date?
        public let isPaused: Bool

        public init(id: String, endDate: Date?, isPaused: Bool) {
            self.id = id
            self.endDate = endDate
            self.isPaused = isPaused
        }
    }

    /// Pending request as seen from `UNUserNotificationCenter`.
    public struct PendingEntry: Equatable {
        public let identifier: String
        public let fireDate: Date?

        public init(identifier: String, fireDate: Date?) {
            self.identifier = identifier
            self.fireDate = fireDate
        }
    }

    /// Timers that should *keep* an existing pending notification.
    /// Active, non-paused, `endDate > now` — **no grace** (I5).
    public static func keepEndDates(
        for timers: [TimerSnapshot],
        now: Date
    ) -> [String: Date] {
        endDates(for: timers, cutoff: now)
    }

    /// Timers eligible for a *new* schedule.
    /// Active, non-paused, `endDate > now + grace` (FR-007).
    public static func addEndDates(
        for timers: [TimerSnapshot],
        now: Date
    ) -> [String: Date] {
        endDates(for: timers, cutoff: now.addingTimeInterval(graceInterval))
    }

    /// Backward-compatible alias used by older tests — same as `addEndDates`.
    public static func desiredSnapshots(
        for timers: [TimerSnapshot],
        now: Date
    ) -> [String: Date] {
        addEndDates(for: timers, now: now)
    }

    private static func endDates(
        for timers: [TimerSnapshot],
        cutoff: Date
    ) -> [String: Date] {
        var result: [String: Date] = [:]
        for timer in timers where !timer.isPaused {
            guard let endDate = timer.endDate else { continue }
            guard endDate > cutoff else { continue }
            result[timer.id] = endDate
        }
        return result
    }

    /// Diff pending vs desired.
    /// - Remove: not in `keepEndDates`, or fireDate ≠ desired endDate.
    /// - Add: in `addEndDates` and not already present with matching date.
    public static func reconcileDiff(
        pending: [PendingEntry],
        keepEndDates: [String: Date],
        addEndDates: [String: Date]
    ) -> (remove: [String], add: [String: Date]) {
        var remove: [String] = []
        var presentMatching: Set<String> = []

        for entry in pending {
            guard let timerId = timerId(from: entry.identifier) else {
                // Outside our namespace — leave untouched.
                continue
            }
            guard let desiredDate = keepEndDates[timerId] else {
                remove.append(entry.identifier)
                continue
            }
            if let fireDate = entry.fireDate {
                if abs(fireDate.timeIntervalSince(desiredDate)) > endDateMatchTolerance {
                    remove.append(entry.identifier)
                    continue
                }
                presentMatching.insert(timerId)
            } else {
                // Can't verify fire date — remove and let add path re-schedule
                // if still eligible.
                remove.append(entry.identifier)
            }
        }

        var add: [String: Date] = [:]
        for (timerId, endDate) in addEndDates where !presentMatching.contains(timerId) {
            add[timerId] = endDate
        }
        return (remove, add)
    }

    /// Id-only diff (no fire-date check). Prefer the `PendingEntry`
    /// overload for production scheduling.
    public static func reconcileDiff(
        pendingIdentifiers: [String],
        desiredTimerIds: Set<String>
    ) -> (remove: [String], add: [String]) {
        var remove: [String] = []
        var stillPresentIds: Set<String> = []
        for identifier in pendingIdentifiers {
            if let timerId = timerId(from: identifier) {
                if desiredTimerIds.contains(timerId) {
                    stillPresentIds.insert(timerId)
                } else {
                    remove.append(identifier)
                }
            }
        }
        var add: [String] = []
        for timerId in desiredTimerIds where !stillPresentIds.contains(timerId) {
            add.append(identifier(for: timerId))
        }
        return (remove, add)
    }
}
