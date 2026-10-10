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
    // MARK: - Update dedupe (review 2026.10.09 №4b)

    private typealias Coordinator = TimerLiveActivityCoordinator
    private typealias State = RecipeTimerActivityAttributes.ContentState

    private func runningState(endingIn seconds: TimeInterval, total: TimeInterval = 600, at now: Date) -> State {
        State(
            phase: .running,
            endDate: now.addingTimeInterval(seconds),
            pausedRemainingSeconds: Int(total),
            startedAt: now.addingTimeInterval(seconds - total),
            totalDuration: total,
            recipeName: "Pasta",
            recipeThumbnailName: "la-thumb-r1-1700000000.jpg",
            syncedAt: now
        )
    }

    func testRendersIdentically_SkipsTickThatOnlyBumpsSyncedAt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let shown = runningState(endingIn: 290, at: now) // "4m" for the next 50 s
        var next = shown
        next.syncedAt = now.addingTimeInterval(3)
        let lastKey = Coordinator.RenderKey(state: shown, now: now)

        XCTAssertTrue(Coordinator.rendersIdentically(
            shown: shown, next: next, lastKey: lastKey, now: now.addingTimeInterval(3)
        ))
    }

    func testRendersIdentically_UpdatesWhenNothingPushedThisProcess() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let state = runningState(endingIn: 300, at: now)
        XCTAssertFalse(
            Coordinator.rendersIdentically(shown: state, next: state, lastKey: nil, now: now),
            "First sync after launch must re-render (extension UI may have changed)"
        )
    }

    func testRendersIdentically_UpdatesWhenContentDiffers() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let shown = runningState(endingIn: 300, at: now)
        let lastKey = Coordinator.RenderKey(state: shown, now: now)

        var paused = shown
        paused.phase = .paused
        XCTAssertFalse(Coordinator.rendersIdentically(shown: shown, next: paused, lastKey: lastKey, now: now))

        var renamed = shown
        renamed.recipeName = "Soup"
        XCTAssertFalse(Coordinator.rendersIdentically(shown: shown, next: renamed, lastKey: lastKey, now: now))
    }

    /// Accent (last 10% → "soon") and AOD compact text are computed from the clock
    /// at render time, so their transitions must still push an update.
    func testRendersIdentically_UpdatesOnClockDerivedTransitions() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let state = runningState(endingIn: 61, total: 700, at: now)
        let lastKey = Coordinator.RenderKey(state: state, now: now)
        XCTAssertEqual(lastKey.accent, .soon)
        XCTAssertEqual(lastKey.compactText, "1m")

        XCTAssertTrue(Coordinator.rendersIdentically(
            shown: state, next: state, lastKey: lastKey, now: now.addingTimeInterval(1)
        ))
        XCTAssertFalse(
            Coordinator.rendersIdentically(shown: state, next: state, lastKey: lastKey, now: now.addingTimeInterval(2)),
            "\"1m\" → \"59s\" changes the AOD text"
        )

        // 71 s left of 700 is still "normal" (soon < 70 s) and also "1m": only the accent flips.
        let normalKey = Coordinator.RenderKey(state: state, now: now.addingTimeInterval(-10))
        XCTAssertEqual(normalKey.accent, .normal)
        XCTAssertEqual(normalKey.compactText, "1m")
        XCTAssertFalse(
            Coordinator.rendersIdentically(shown: state, next: state, lastKey: normalKey, now: now),
            "normal → soon accent must re-render"
        )
    }
}
