import SwiftData
import XCTest
@testable import RecipeScalerNative

/// Regression tests for mobile timer panel countdown (spec: panel must tick every second).
@MainActor
final class TimerPanelRefreshTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Panel refresh cadence (TimerManager backend)

    func testPanelDisplayedSecond_decreasesEverySecondWhileCountdownRunning() {
        let timer = runningTimer(endTime: anchor.addingTimeInterval(108))

        let seconds = (0..<5).map { offset in
            TimerUtils.panelDisplayedSeconds(for: timer, now: anchor.addingTimeInterval(Double(offset)))
        }

        XCTAssertEqual(seconds, [108, 107, 106, 105, 104])
    }

    func testPanelDisplayedSecond_decreasesEverySecondWhileOverdue() {
        let timer = runningTimer(endTime: anchor.addingTimeInterval(-108))

        let seconds = (0..<5).map { offset in
            TimerUtils.panelDisplayedSeconds(for: timer, now: anchor.addingTimeInterval(Double(offset)))
        }

        XCTAssertEqual(seconds, [-108, -109, -110, -111, -112])
    }

    func testAdvancePanelDisplayedSecond_triggersRefreshEverySecondWhileOverdue() {
        let timer = runningTimer(endTime: anchor.addingTimeInterval(-108))
        var lastDisplayedSeconds: [String: Int] = [:]

        let refreshFlags = (0..<5).map { offset in
            TimerUtils.advancePanelDisplayedSecond(
                lastDisplayedSeconds: &lastDisplayedSeconds,
                timer: timer,
                now: anchor.addingTimeInterval(Double(offset))
            )
        }

        XCTAssertEqual(refreshFlags, [true, true, true, true, true])
    }

    func testLegacyCeilPanelFormula_wouldFreezeRefreshWhileOverdue() {
        let timer = runningTimer(endTime: anchor.addingTimeInterval(-108))
        var lastLegacyDisplayed: Int?

        let legacyRefreshFlags = (0..<5).map { offset -> Bool in
            let remaining = timer.endTime!.timeIntervalSince(anchor.addingTimeInterval(Double(offset)))
            let legacyDisplayed = max(0, Int(ceil(remaining)))
            let changed = lastLegacyDisplayed != legacyDisplayed
            lastLegacyDisplayed = legacyDisplayed
            return changed
        }

        XCTAssertEqual(legacyRefreshFlags, [true, false, false, false, false],
                       "Old max(0, ceil) formula freezes panel refresh after the first overdue tick")
    }

    func testAdvancePanelDisplayedSecond_doesNotRefreshWhenPaused() {
        let timer = runningTimer(endTime: anchor.addingTimeInterval(108))
        timer.pause()
        timer.remainingTime = 108
        var lastDisplayedSeconds: [String: Int] = [:]

        let first = TimerUtils.advancePanelDisplayedSecond(
            lastDisplayedSeconds: &lastDisplayedSeconds,
            timer: timer,
            now: anchor
        )
        let second = TimerUtils.advancePanelDisplayedSecond(
            lastDisplayedSeconds: &lastDisplayedSeconds,
            timer: timer,
            now: anchor.addingTimeInterval(1)
        )

        XCTAssertTrue(first)
        XCTAssertFalse(second, "Paused timers must not trigger per-second panel refresh")
    }

    // MARK: - UI contract (TimelineView drives live countdown)

    func testMobileTimerPanelSourceUsesTimelineViewForLiveCountdown() throws {
        let panelURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RecipeScalerNative/Views/MobileTimerPanel.swift")
        let source = try String(contentsOf: panelURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("TimelineView(.periodic(from: .now, by: 1))"),
            "Mobile timer panel must use TimelineView so countdown ticks without relying on @Observable alone"
        )
        XCTAssertTrue(
            source.contains("TimerUtils.remainingSeconds(for: timer, now: context.date)"),
            "TimelineView content must compute remaining from endTime + timeline date"
        )
    }

    // MARK: - Regression MIK-187: tick must not mutate per-timer state or reassign activeTimers

    /// `updateRunningTimers()` must not write `timer.remainingTime` for running timers.
    /// Live countdown is owned by `TimelineView` in `MobileTimerPanel`; mutating the
    /// `@Model` on every tick invalidated the entire observing view tree.
    func testUpdateRunningTimers_doesNotMutateRemainingTimeForRunningTimer() throws {
        let manager = try makeTimerManager()
        let timer = manager.createAndStartTimer(name: "Pasta", duration: 120, type: .seconds)
        let baselineRemaining = timer.remainingTime

        manager.tickUpdateRunningTimersForTests()

        XCTAssertEqual(
            timer.remainingTime,
            baselineRemaining,
            "Tick must not mutate remainingTime for a running timer (drives @Observable invalidation)"
        )
    }

    /// `updateRunningTimers()` must not reassign `activeTimers`. The array is read by
    /// `MobileTimerPanelBottomPaddingModifier` (and thus `.safeAreaInset` on every
    /// tab root); reassigning it once per second caused layout thrash on tab roots.
    func testUpdateRunningTimers_doesNotRefreshActiveTimersEachTick() throws {
        let manager = try makeTimerManager()
        _ = manager.createAndStartTimer(name: "Pasta", duration: 120, type: .seconds)

        let before = manager.activeTimers
        let beforeCount = before.count
        let beforeIds = before.map(\.id)

        manager.tickUpdateRunningTimersForTests()

        XCTAssertEqual(manager.activeTimers.count, beforeCount)
        XCTAssertEqual(manager.activeTimers.map(\.id), beforeIds,
                       "Tick must not reassign activeTimers — drives safeAreaInset on tab roots")
    }

    // MARK: - Helpers

    private func makeTimerManager() throws -> TimerManager {
        let modelContainer = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(modelContainer)
        let container = try AppContainer(modelContext: context)
        return container.timer
    }

    private func runningTimer(endTime: Date) -> RecipeTimer {
        let timer = RecipeTimer(
            id: "panel-refresh-test",
            name: "Test",
            duration: 120,
            type: .minutes,
            isRunning: true,
            isPaused: false
        )
        timer.endTime = endTime
        return timer
    }
}
