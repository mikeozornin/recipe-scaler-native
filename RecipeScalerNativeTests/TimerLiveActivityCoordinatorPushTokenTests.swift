//
//  TimerLiveActivityCoordinatorPushTokenTests.swift
//
//  Spec 058 — coordinator push-token + sync-policy contracts that are
//  reachable without ActivityKit (off-device unit host).
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class TimerLiveActivityCoordinatorPushTokenTests: XCTestCase {

    // MARK: - Background running skip policy

    func testShouldSkip_UserActionNeverSkipsBackgroundRunning() {
        let skip = TimerLiveActivityCoordinator.shouldSkipBackgroundRunningUpdate(
            phase: .running,
            appIsActive: false,
            hasExistingActivity: true,
            policy: .userAction
        )
        XCTAssertFalse(
            skip,
            "Lock Screen / in-app resume must update LA while backgrounded (R7)"
        )
    }

    func testShouldSkip_ProgressSkipsBackgroundRunningWhenActivityExists() {
        let skip = TimerLiveActivityCoordinator.shouldSkipBackgroundRunningUpdate(
            phase: .running,
            appIsActive: false,
            hasExistingActivity: true,
            policy: .progress
        )
        XCTAssertTrue(
            skip,
            "Progress ticks must not revive APNs-paused cards with stale running"
        )
    }

    func testShouldSkip_ReconcileSkipsBackgroundRunningWhenActivityExists() {
        let skip = TimerLiveActivityCoordinator.shouldSkipBackgroundRunningUpdate(
            phase: .running,
            appIsActive: false,
            hasExistingActivity: true,
            policy: .reconcile
        )
        XCTAssertTrue(skip)
    }

    func testShouldSkip_AllowsPausedInBackground() {
        for policy: LiveActivitySyncPolicy in [.userAction, .progress, .reconcile] {
            let skip = TimerLiveActivityCoordinator.shouldSkipBackgroundRunningUpdate(
                phase: .paused,
                appIsActive: false,
                hasExistingActivity: true,
                policy: policy
            )
            XCTAssertFalse(skip, "paused updates must apply for \(policy)")
        }
    }

    func testShouldSkip_AllowsRunningWhenActive() {
        let skip = TimerLiveActivityCoordinator.shouldSkipBackgroundRunningUpdate(
            phase: .running,
            appIsActive: true,
            hasExistingActivity: true,
            policy: .progress
        )
        XCTAssertFalse(skip)
    }

    func testShouldSkip_AllowsNewActivityRequestWithoutExisting() {
        let skip = TimerLiveActivityCoordinator.shouldSkipBackgroundRunningUpdate(
            phase: .running,
            appIsActive: false,
            hasExistingActivity: false,
            policy: .reconcile
        )
        XCTAssertFalse(skip, "brand-new Activity.request must not be blocked")
    }

    // MARK: - Foreground progress gate

    func testProgressGate_BlockedWhileSuppressFlagSet() {
        XCTAssertFalse(
            TimerManager.shouldAllowProgressLiveActivitySync(
                appIsActive: true,
                suppressProgressSync: true
            )
        )
    }

    func testProgressGate_AllowedWhenActiveAndNotSuppressed() {
        XCTAssertTrue(
            TimerManager.shouldAllowProgressLiveActivitySync(
                appIsActive: true,
                suppressProgressSync: false
            )
        )
    }

    func testProgressGate_BlockedWhenInactive() {
        XCTAssertFalse(
            TimerManager.shouldAllowProgressLiveActivitySync(
                appIsActive: false,
                suppressProgressSync: false
            )
        )
    }

    // MARK: - end(timerId:) — single id

    func testEndById_InvokesUnregisterEvenWhenActivityNotCached() async {
        let stub = StubPushRegistrar()
        let coordinator = TimerLiveActivityCoordinator(pushRegistrar: stub)

        await coordinator.end(timerId: "timer_uncached")

        XCTAssertEqual(stub.unregisterCalls, ["timer_uncached"])
        XCTAssertEqual(stub.registerCalls, 0)
    }

    func testEndById_UnregisterRunsExactlyOncePerCall() async {
        let stub = StubPushRegistrar()
        let coordinator = TimerLiveActivityCoordinator(pushRegistrar: stub)

        await coordinator.end(timerId: "timer_a")
        await coordinator.end(timerId: "timer_b")
        await coordinator.end(timerId: "timer_a")

        XCTAssertEqual(stub.unregisterCalls, ["timer_a", "timer_b", "timer_a"])
    }

    // MARK: - endAll / clearForLogout

    func testEndAll_NoopWhenNothingCachedStillSafe() async {
        let stub = StubPushRegistrar()
        let coordinator = TimerLiveActivityCoordinator(pushRegistrar: stub)

        await coordinator.endAll()

        XCTAssertTrue(stub.unregisterCalls.isEmpty)
        XCTAssertEqual(stub.clearAllCachedTokensCalls, 0)
    }

    func testClearForLogout_ClearsTokenCacheEvenWithNoActivities() async {
        let stub = StubPushRegistrar()
        let coordinator = TimerLiveActivityCoordinator(pushRegistrar: stub)

        await coordinator.clearForLogout()

        XCTAssertEqual(
            stub.clearAllCachedTokensCalls,
            1,
            "clearForLogout must wipe UserDefaults token keys even when endAll is a no-op"
        )
        XCTAssertTrue(stub.unregisterCalls.isEmpty)
    }

    // MARK: - stub

    @MainActor
    private final class StubPushRegistrar: LiveActivityPushRegistering {
        private(set) var registerCalls = 0
        private(set) var unregisterCalls: [String] = []
        private(set) var clearAllCachedTokensCalls = 0

        func hasCachedToken(timerId: String) -> Bool { false }
        func clearAllCachedTokens() { clearAllCachedTokensCalls += 1 }

        @discardableResult
        func register(timerId: String, tokenHex: String) async -> Bool {
            registerCalls += 1
            return true
        }

        func unregister(timerId: String) async {
            unregisterCalls.append(timerId)
        }
    }
}
