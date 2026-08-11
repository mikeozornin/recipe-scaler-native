//
//  WatchExpiryNotificationSchedulerTests.swift
//  RecipeScalerNativeTests
//
//  Spec 062 — pure-logic tests for `WatchExpiryNotificationPlanner`
//  (identifier parsing, grace interval, reconcile diff).
//
//  Actor-level scheduler tests would need a watch-test target (currently
//  doesn't exist); instead the testable logic lives in RecipeScalerCore and
//  is covered here.
//

import XCTest
@testable import RecipeScalerCore

final class WatchExpiryNotificationSchedulerTests: XCTestCase {

    // MARK: - Identifier helpers

    func test_identifier_for_timerId() {
        XCTAssertEqual(
            WatchExpiryNotificationPlanner.identifier(for: "abc"),
            "watch-timer-abc-complete"
        )
        XCTAssertEqual(
            WatchExpiryNotificationPlanner.identifier(for: "uuid-1234"),
            "watch-timer-uuid-1234-complete"
        )
    }

    func test_timerId_from_valid_identifier() {
        XCTAssertEqual(
            WatchExpiryNotificationPlanner.timerId(from: "watch-timer-abc-complete"),
            "abc"
        )
        XCTAssertEqual(
            WatchExpiryNotificationPlanner.timerId(from: "watch-timer-uuid-1234-complete"),
            "uuid-1234"
        )
    }

    func test_timerId_from_invalid_identifier_returns_nil() {
        XCTAssertNil(WatchExpiryNotificationPlanner.timerId(from: "foo"))
        XCTAssertNil(WatchExpiryNotificationPlanner.timerId(from: "watch-timer-no-suffix"))
        XCTAssertNil(WatchExpiryNotificationPlanner.timerId(from: "timer-abc-complete"))
        XCTAssertNil(WatchExpiryNotificationPlanner.timerId(from: "random-id"))
        XCTAssertNil(WatchExpiryNotificationPlanner.timerId(from: ""))
        // Identifier with only prefix and suffix, no timerId body.
        XCTAssertNil(WatchExpiryNotificationPlanner.timerId(from: "watch-timer--complete"))
    }

    // MARK: - desiredSnapshots

    func test_desiredSnapshots_schedules_for_active_timer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let endDate = now.addingTimeInterval(60)
        let snapshot = WatchExpiryNotificationPlanner.TimerSnapshot(
            id: "t1", endDate: endDate, isPaused: false
        )
        let result = WatchExpiryNotificationPlanner.desiredSnapshots(for: [snapshot], now: now)
        XCTAssertEqual(result, ["t1": endDate])
    }

    func test_desiredSnapshots_skips_paused_timer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let endDate = now.addingTimeInterval(60)
        let snapshot = WatchExpiryNotificationPlanner.TimerSnapshot(
            id: "t1", endDate: endDate, isPaused: true
        )
        let result = WatchExpiryNotificationPlanner.desiredSnapshots(for: [snapshot], now: now)
        XCTAssertTrue(result.isEmpty)
    }

    func test_desiredSnapshots_skips_nil_endDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = WatchExpiryNotificationPlanner.TimerSnapshot(
            id: "t1", endDate: nil, isPaused: false
        )
        let result = WatchExpiryNotificationPlanner.desiredSnapshots(for: [snapshot], now: now)
        XCTAssertTrue(result.isEmpty)
    }

    func test_desiredSnapshots_skips_expired_timer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let endDate = now.addingTimeInterval(-60)
        let snapshot = WatchExpiryNotificationPlanner.TimerSnapshot(
            id: "t1", endDate: endDate, isPaused: false
        )
        let result = WatchExpiryNotificationPlanner.desiredSnapshots(for: [snapshot], now: now)
        XCTAssertTrue(result.isEmpty)
    }

    func test_desiredSnapshots_skips_within_grace() {
        let now = Date(timeIntervalSince1970: 1_000)
        // 3 seconds in the future — inside grace (5s).
        let endDate = now.addingTimeInterval(3)
        let snapshot = WatchExpiryNotificationPlanner.TimerSnapshot(
            id: "t1", endDate: endDate, isPaused: false
        )
        let result = WatchExpiryNotificationPlanner.desiredSnapshots(for: [snapshot], now: now)
        XCTAssertTrue(result.isEmpty)
    }

    func test_desiredSnapshots_just_outside_grace() {
        let now = Date(timeIntervalSince1970: 1_000)
        // 6 seconds — strictly greater than grace (5s), should schedule.
        let endDate = now.addingTimeInterval(6)
        let snapshot = WatchExpiryNotificationPlanner.TimerSnapshot(
            id: "t1", endDate: endDate, isPaused: false
        )
        let result = WatchExpiryNotificationPlanner.desiredSnapshots(for: [snapshot], now: now)
        XCTAssertEqual(result, ["t1": endDate])
    }

    func test_desiredSnapshots_multiple_timers() {
        let now = Date(timeIntervalSince1970: 1_000)
        let end1 = now.addingTimeInterval(60)
        let end2 = now.addingTimeInterval(120)
        let snapshots = [
            WatchExpiryNotificationPlanner.TimerSnapshot(id: "t1", endDate: end1, isPaused: false),
            WatchExpiryNotificationPlanner.TimerSnapshot(id: "t2", endDate: end2, isPaused: false),
            WatchExpiryNotificationPlanner.TimerSnapshot(id: "t3", endDate: end1, isPaused: true),
            WatchExpiryNotificationPlanner.TimerSnapshot(id: "t4", endDate: nil, isPaused: false),
            WatchExpiryNotificationPlanner.TimerSnapshot(id: "t5", endDate: now.addingTimeInterval(2), isPaused: false),
        ]
        let result = WatchExpiryNotificationPlanner.desiredSnapshots(for: snapshots, now: now)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["t1"], end1)
        XCTAssertEqual(result["t2"], end2)
    }

    // MARK: - reconcileDiff

    func test_reconcileDiff_schedules_for_active_timer() {
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pendingIdentifiers: [],
            desiredTimerIds: ["t1"]
        )
        XCTAssertTrue(diff.remove.isEmpty)
        XCTAssertEqual(diff.add, ["watch-timer-t1-complete"])
    }

    func test_reconcileDiff_no_change_when_already_pending() {
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pendingIdentifiers: ["watch-timer-t1-complete"],
            desiredTimerIds: ["t1"]
        )
        XCTAssertTrue(diff.remove.isEmpty)
        XCTAssertTrue(diff.add.isEmpty)
    }

    func test_reconcileDiff_cancels_orphan_pending() {
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pendingIdentifiers: [
                "watch-timer-t1-complete",
                "watch-timer-t2-complete",
            ],
            desiredTimerIds: ["t1"]
        )
        // t2 is orphan (was scheduled, no longer desired) → remove.
        XCTAssertEqual(diff.remove, ["watch-timer-t2-complete"])
        XCTAssertTrue(diff.add.isEmpty)
    }

    func test_reconcileDiff_ignores_non_watch_identifiers() {
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pendingIdentifiers: [
                "t1-complete",  // iPhone namespace, not ours.
                "random-id",
                "watch-timer-t1-complete",
            ],
            desiredTimerIds: ["t1"]
        )
        XCTAssertTrue(diff.remove.isEmpty)
        XCTAssertTrue(diff.add.isEmpty)
    }

    func test_reconcileDiff_add_and_remove_at_once() {
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pendingIdentifiers: ["watch-timer-t1-complete"],
            desiredTimerIds: ["t2"]
        )
        XCTAssertEqual(diff.remove, ["watch-timer-t1-complete"])
        XCTAssertEqual(diff.add, ["watch-timer-t2-complete"])
    }

    func test_reconcileDiff_paused_timer_is_not_desired() {
        // Pause = timerId drops out of desired set → diff should remove.
        // This test documents the contract for the actor-level pause flow.
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pendingIdentifiers: ["watch-timer-t1-complete"],
            desiredTimerIds: []
        )
        XCTAssertEqual(diff.remove, ["watch-timer-t1-complete"])
        XCTAssertTrue(diff.add.isEmpty)
    }

    func test_reconcileDiff_double_reconcile_single_pending_per_timer() {
        // Simulate two consecutive reconciles. After first, pending = [t1].
        // Second reconcile with same desired → no change.
        var desired: Set<String> = ["t1"]
        var pending: [String] = []

        let r1 = WatchExpiryNotificationPlanner.reconcileDiff(
            pendingIdentifiers: pending,
            desiredTimerIds: desired
        )
        // After r1: pending grows by `add`.
        pending.append(contentsOf: r1.add)

        let r2 = WatchExpiryNotificationPlanner.reconcileDiff(
            pendingIdentifiers: pending,
            desiredTimerIds: desired
        )
        XCTAssertTrue(r2.remove.isEmpty)
        XCTAssertTrue(r2.add.isEmpty, "Second reconcile should not add duplicate")
        _ = desired  // keep compiler honest
    }

    // MARK: - Constants

    func test_constants_are_stable() {
        XCTAssertEqual(WatchExpiryNotificationPlanner.identifierPrefix, "watch-timer-")
        XCTAssertEqual(WatchExpiryNotificationPlanner.identifierSuffix, "-complete")
        XCTAssertEqual(WatchExpiryNotificationPlanner.graceInterval, 5)
    }

    /// Regression: prefs OFF must round-trip via bool(forKey:) after set(false).
    func test_userDefaults_false_roundtrip_uses_bool_forKey() {
        let suite = "WatchExpiryNotificationSchedulerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let key = "watchExpiryNotificationsEnabled"
        defaults.register(defaults: [key: true])
        defaults.set(false, forKey: key)

        XCTAssertFalse(defaults.bool(forKey: key))
        XCTAssertTrue(defaults.bool(forKey: key) == false, "bool(forKey:) must return stored false")
    }

    // MARK: - keep vs add (I5 / grace)

    func test_keepEndDates_retains_timer_inside_grace() {
        let now = Date(timeIntervalSince1970: 1_000)
        let endDate = now.addingTimeInterval(3) // inside grace for add
        let snapshot = WatchExpiryNotificationPlanner.TimerSnapshot(
            id: "t1", endDate: endDate, isPaused: false
        )
        let keep = WatchExpiryNotificationPlanner.keepEndDates(for: [snapshot], now: now)
        let add = WatchExpiryNotificationPlanner.addEndDates(for: [snapshot], now: now)
        XCTAssertEqual(keep, ["t1": endDate], "I5: already-future timer stays in keep")
        XCTAssertTrue(add.isEmpty, "FR-007: no new schedule inside grace")
    }

    func test_reconcileDiff_keeps_pending_inside_grace_without_readd() {
        let now = Date(timeIntervalSince1970: 1_000)
        let endDate = now.addingTimeInterval(3)
        let pending = [
            WatchExpiryNotificationPlanner.PendingEntry(
                identifier: "watch-timer-t1-complete",
                fireDate: endDate
            )
        ]
        let keep = ["t1": endDate]
        let add: [String: Date] = [:]
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pending: pending,
            keepEndDates: keep,
            addEndDates: add
        )
        XCTAssertTrue(diff.remove.isEmpty, "Must not cancel pending solely because grace started")
        XCTAssertTrue(diff.add.isEmpty)
    }

    func test_reconcileDiff_removes_and_readds_on_endDate_drift() {
        let oldEnd = Date(timeIntervalSince1970: 1_060)
        let newEnd = Date(timeIntervalSince1970: 1_200)
        let pending = [
            WatchExpiryNotificationPlanner.PendingEntry(
                identifier: "watch-timer-t1-complete",
                fireDate: oldEnd
            )
        ]
        let keep = ["t1": newEnd]
        let add = ["t1": newEnd]
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pending: pending,
            keepEndDates: keep,
            addEndDates: add
        )
        XCTAssertEqual(diff.remove, ["watch-timer-t1-complete"])
        XCTAssertEqual(diff.add, ["t1": newEnd])
    }

    func test_reconcileDiff_matching_endDate_is_noop() {
        let end = Date(timeIntervalSince1970: 1_060)
        let pending = [
            WatchExpiryNotificationPlanner.PendingEntry(
                identifier: "watch-timer-t1-complete",
                fireDate: end
            )
        ]
        let keep = ["t1": end]
        let add = ["t1": end]
        let diff = WatchExpiryNotificationPlanner.reconcileDiff(
            pending: pending,
            keepEndDates: keep,
            addEndDates: add
        )
        XCTAssertTrue(diff.remove.isEmpty)
        XCTAssertTrue(diff.add.isEmpty)
    }
}
