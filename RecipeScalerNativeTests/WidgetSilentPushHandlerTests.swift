//
//  WidgetSilentPushHandlerTests.swift
//
//  Spec 030 Phase B4 — silent wake detection must not treat alert-only 023
//  completions as widget refresh, and must accept reason / pure silent.
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

final class WidgetSilentPushHandlerTests: XCTestCase {
    func testShouldRefresh_PureSilentContentAvailable() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1]
        ]
        XCTAssertTrue(WidgetSilentPushHandler.shouldRefreshWidget(userInfo: userInfo))
    }

    func testShouldRefresh_ExplicitReasonTimers() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1, "alert": "Timer done"],
            "reason": "timers"
        ]
        XCTAssertTrue(WidgetSilentPushHandler.shouldRefreshWidget(userInfo: userInfo))
    }

    func testShouldRefresh_ExplicitReasonWidgetRefresh() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Done"]],
            "reason": "widget-refresh"
        ]
        XCTAssertTrue(WidgetSilentPushHandler.shouldRefreshWidget(userInfo: userInfo))
    }

    func testShouldNotRefresh_AlertOnlyWithoutContentAvailable() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Timer finished", "body": "Boil"]],
            "timerId": "t1"
        ]
        XCTAssertFalse(
            WidgetSilentPushHandler.shouldRefreshWidget(userInfo: userInfo),
            "023 alert-only completion must not be classified as widget silent refresh"
        )
    }

    func testShouldNotRefresh_ContentAvailableWithAlertAndNoReason() {
        // Alert + content-available without reason: leave to UN presentation;
        // do not treat as widget-refresh (avoids double work on completion push).
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "content-available": 1,
                "alert": ["title": "Timer finished"]
            ],
            "timerId": "t1"
        ]
        XCTAssertFalse(WidgetSilentPushHandler.shouldRefreshWidget(userInfo: userInfo))
    }

    // MARK: - pending-local gate (review finding #1 on silent path)

    func testRefreshSnapshotFromServer_PendingLocalBlocksOverwrite() async {
        // Simulate an in-flight optimistic Lock Screen pause: pendingLocalUntil
        // is set. Silent wake arriving in this window must not POST server truth
        // over the snapshot.
        let pendingKey = "widgets.timerSnapshot.pendingLocalUntil"
        let snapshotKey = "widgets.timerSnapshot"
        let defaults = AppGroup.userDefaults!
        let originalPending = defaults.object(forKey: pendingKey)
        let originalSnapshot = defaults.data(forKey: snapshotKey)
        defer {
            if let originalPending {
                defaults.set(originalPending, forKey: pendingKey)
            } else {
                defaults.removeObject(forKey: pendingKey)
            }
            if let originalSnapshot {
                defaults.set(originalSnapshot, forKey: snapshotKey)
            } else {
                defaults.removeObject(forKey: snapshotKey)
            }
        }

        // Seed an existing snapshot so we can prove it survives.
        let seeded = TimerSnapshotDocument(
            timers: [
                TimerSnapshot(
                    id: "t-paused",
                    name: "Pasta",
                    recipeId: nil,
                    recipeName: nil,
                    endDate: nil,
                    pausedRemainingSeconds: 30,
                    phase: .paused,
                    totalDurationSeconds: 120
                )
            ],
            generatedAt: Date.distantPast
        )
        TimerSnapshotStore.save(seeded)

        // Mark pending for 15s — Intent → TimerManager drain window.
        TimerSnapshotStore.markPendingLocalMutation(ttl: 15, now: Date())
        XCTAssertTrue(TimerSnapshotStore.hasPendingLocalMutation(now: Date()))

        // Silent refresh should short-circuit and leave the paused snapshot intact.
        let wrote = await WidgetSilentPushHandler.refreshSnapshotFromServer()
        XCTAssertFalse(wrote, "Pending-local gate must block silent push overwrite")

        let after = TimerSnapshotStore.load()
        XCTAssertEqual(after.timers.first?.phase, .paused)
        XCTAssertEqual(after.timers.first?.id, "t-paused")
    }
}
