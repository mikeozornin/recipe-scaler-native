import XCTest
@testable import RecipeScalerNative

@MainActor
final class OfflineBannerGateTests: XCTestCase {
    /// Threshold (s) used across tests. Kept small enough to keep the suite fast,
    /// large enough to let the runloop observe task cancellation between transitions.
    private let testThreshold: Double = 0.2

    // MARK: - FR-002, invariants

    func testInitiallyHidden() {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)
        XCTAssertFalse(gate.isVisible, "Gate must be hidden immediately after init")
    }

    // MARK: - User Story 1 (no flash on short dip)

    func testShortDipDoesNotShow() async throws {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)

        gate.update(isNotConnected: true)
        // Sleep well below threshold, then reconnect before the arm task fires.
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 0.4 * 1_000_000_000))
        gate.update(isNotConnected: false)

        // Give the (cancelled) arm task time to no-op.
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 2 * 1_000_000_000))
        XCTAssertFalse(gate.isVisible, "Short offline dip below threshold must not show the banner")
    }

    // MARK: - User Story 2 (real offline > threshold shows)

    func testLongOfflineShows() async throws {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)

        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 3 * 1_000_000_000))

        XCTAssertTrue(gate.isVisible, "Continuous offline longer than threshold must show the banner")
    }

    // MARK: - User Story 3 (instant hide on reconnect)

    func testReconnectHidesInstantly() async throws {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)

        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 3 * 1_000_000_000))
        XCTAssertTrue(gate.isVisible, "Precondition: banner shown after threshold")

        gate.update(isNotConnected: false)
        // Yield once so the synchronous `isVisible = false` is observable.
        await Task.yield()
        XCTAssertFalse(gate.isVisible, "Reconnect must hide the banner immediately, no delay")
    }

    // MARK: - Re-arm after reconnect

    func testReArmAfterReconnect() async throws {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)

        // First offline episode → show.
        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 3 * 1_000_000_000))
        XCTAssertTrue(gate.isVisible)

        // Reconnect → hide.
        gate.update(isNotConnected: false)
        await Task.yield()
        XCTAssertFalse(gate.isVisible)

        // Second offline episode → must show again after threshold (re-arm works).
        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 3 * 1_000_000_000))
        XCTAssertTrue(gate.isVisible, "Gate must re-arm after a reconnect → offline transition")
    }

    // MARK: - FR-005 (dedupe repeated true)

    func testRapidTransitionsDoNotShow() async throws {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)

        // Several transitions, each well below threshold, with an instantaneous
        // reconnect in between so the arm task restarts every time.
        for _ in 0..<4 {
            gate.update(isNotConnected: true)
            try await Task.sleep(nanoseconds: UInt64(testThreshold * 0.3 * 1_000_000_000))
            gate.update(isNotConnected: false)
            try await Task.sleep(nanoseconds: UInt64(testThreshold * 0.1 * 1_000_000_000))
        }

        // Total duration is multiple thresholds, but no single continuous offline
        // window reached threshold → banner must stay hidden.
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 2 * 1_000_000_000))
        XCTAssertFalse(gate.isVisible, "Rapid transitions below threshold must never show the banner")
    }

    // MARK: - FR-005 (repeated true without intermediate false is a no-op)

    func testDuplicateTrueDoesNotReArm() async throws {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)

        // Arm, then keep sending true without ever going false — must not reset
        // the running arm task's deadline.
        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 0.5 * 1_000_000_000))
        gate.update(isNotConnected: true)
        gate.update(isNotConnected: true)

        try await Task.sleep(nanoseconds: UInt64(testThreshold * 2 * 1_000_000_000))
        XCTAssertTrue(gate.isVisible, "Duplicate true must not re-arm or reset the deadline")
    }

    // MARK: - US1 (background time does not count)

    func testUnlockAfterBackgroundResetDoesNotShow() async throws {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)

        // Old bug: arm while backgrounded, sleep past threshold → banner latches.
        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 3 * 1_000_000_000))
        XCTAssertTrue(gate.isVisible, "Precondition: expired arm would have shown")

        // AppShellView on scenePhase == .background
        gate.update(isNotConnected: false)
        XCTAssertFalse(gate.isVisible)

        // Unlock: still disconnected, then .connecting (still true), then .connected
        // within the threshold — banner must stay hidden.
        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 0.4 * 1_000_000_000))
        gate.update(isNotConnected: true)
        gate.update(isNotConnected: false)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 2 * 1_000_000_000))
        XCTAssertFalse(
            gate.isVisible,
            "Foreground reconnect within threshold after background reset must not show"
        )
    }

    func testForegroundOfflineAfterBackgroundResetShowsAfterThreshold() async throws {
        let gate = OfflineBannerGate(thresholdSeconds: testThreshold)

        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 3 * 1_000_000_000))
        gate.update(isNotConnected: false)

        gate.update(isNotConnected: true)
        try await Task.sleep(nanoseconds: UInt64(testThreshold * 3 * 1_000_000_000))
        XCTAssertTrue(
            gate.isVisible,
            "Real foreground offline after background reset must still show after threshold"
        )
    }
}
