import RecipeScalerCore
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

    /// Regression MIK-187 follow-up: widget snapshot must still be republished on tick.
    /// Review 2026.09.04 №8: the per-second tick must NOT republish the widget
    /// snapshot — `TimerWidgetProvider.getTimeline` builds forward entries
    /// (per-second near the threshold, minute boundaries otherwise) so the
    /// widget advances without a host wakeup every second. Republishing on
    /// every tick woke the widget extension 1 Hz for the whole timer run.
    /// Structural mutations (`refreshPanelTimers`) still republish.
    func testUpdateRunningTimers_doesNotRepublishWidgetSnapshotOnTick() async throws {
        let snapshotStore = TestSnapshotStore()
        snapshotStore.clear()
        let manager = try makeTimerManager(snapshotStore: snapshotStore)
        XCTAssertNil(
            snapshotStore.loadForAssertions().timers
                .first { $0.id.hasPrefix("timer_") },
            "Precondition: no timer snapshot left over from an earlier test"
        )
        _ = manager.createAndStartTimer(name: "Pasta", duration: 120, type: .seconds)

        // `createAndStartTimer` triggers a structural `refreshPanelTimers()` →
        // `persistTimerSnapshot()` debounced 200ms. Drain it so we get a clean
        // baseline `generatedAt` before the tick.
        await manager.drainTimerSnapshotWriteForTests()
        let baselineDocument = snapshotStore.loadForAssertions()
        XCTAssertFalse(baselineDocument.timers.isEmpty,
                       "Structural mutation must have published an initial widget snapshot")

        manager.tickUpdateRunningTimersForTests()

        let afterTickDocument = snapshotStore.loadForAssertions()
        XCTAssertEqual(
            afterTickDocument.generatedAt,
            baselineDocument.generatedAt,
            "Tick must not republish — the widget timeline advances on its own entries"
        )
    }

    /// Companion to the test above (№8): a structural mutation mid-run
    /// (pause) must still republish the snapshot so the widget phase flips.
    func testPauseRepublishesWidgetSnapshot() async throws {
        let snapshotStore = TestSnapshotStore()
        snapshotStore.clear()
        let manager = try makeTimerManager(snapshotStore: snapshotStore)
        XCTAssertNil(
            snapshotStore.loadForAssertions().timers
                .first { $0.id.hasPrefix("timer_") },
            "Precondition: no timer snapshot left over from an earlier test"
        )
        let timer = manager.createAndStartTimer(name: "Pasta", duration: 120, type: .seconds)
        await manager.drainTimerSnapshotWriteForTests()

        manager.pauseTimer(id: timer.id)

        await manager.drainTimerSnapshotWriteForTests()
        let afterPauseDocument = snapshotStore.loadForAssertions()
        XCTAssertTrue(
            afterPauseDocument.timers.contains { $0.pausedRemainingSeconds != nil },
            "Pause must republish the snapshot with the paused phase for the widget"
        )
    }

    // MARK: - Helpers

    /// Per-test widget-snapshot sink. Each test owns a private UserDefaults
    /// suite, so other suites' async teardown cannot wipe the snapshot this
    /// test is draining.
    private final class TestSnapshotStore: TimerSnapshotStoring {
        private let defaults: UserDefaults
        private let suiteName: String

        init() {
            suiteName = "TimerPanelRefreshTests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }

        func save(_ document: TimerSnapshotDocument) {
            TimerSnapshotStore.save(document, to: defaults)
        }

        func clear() {
            TimerSnapshotStore.clear(in: defaults)
        }

        func markPendingLocalMutation(
            ttl: TimeInterval,
            now: Date
        ) {
            TimerSnapshotStore.markPendingLocalMutation(ttl: ttl, now: now, in: defaults)
        }

        func clearPendingLocalMutation() {
            TimerSnapshotStore.clearPendingLocalMutation(in: defaults)
        }

        func loadForAssertions() -> TimerSnapshotDocument {
            TimerSnapshotStore.load(from: defaults)
        }

    }

    // MARK: - Helpers

    private func makeTimerManager(snapshotStore: TimerSnapshotStoring? = nil) throws -> TimerManager {
        let modelContainer = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(modelContainer)
        let container = try AppContainer(
            modelContext: context,
            timerSnapshotStore: snapshotStore ?? TestSnapshotStore()
        )
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
