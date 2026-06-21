import SwiftData
import XCTest
@testable import RecipeScalerNative

/// Regression tests for spec 036 — notification action handlers (+1 / +5 / delete).
@MainActor
final class TimerNotificationActionsTests: XCTestCase {

    private func makeTimerManager() throws -> TimerManager {
        let modelContainer = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(modelContainer)
        let container = try AppContainer(modelContext: context)
        return container.timer
    }

    func testAddTimeExtendsCompletedTimerByOneMinute() throws {
        let manager = try makeTimerManager()
        let timer = manager.createAndStartTimer(name: "Test", duration: 5, type: .seconds)
        timer.hasCompleted = true
        timer.isRunning = false
        timer.remainingTime = 0

        manager.addTime(id: timer.id, minutes: 1)

        let current = manager.timers.first(where: { $0.id == timer.id })
        XCTAssertNotNil(current)
        XCTAssertFalse(current!.hasCompleted)
        XCTAssertTrue(current!.isRunning)
        XCTAssertEqual(current!.endTime!.timeIntervalSinceNow, 60, accuracy: 2)
        XCTAssertGreaterThanOrEqual(current!.remainingTime ?? 0, 55)
    }

    func testAddTimeFromCompletedStateUsesNowAsBase() throws {
        let manager = try makeTimerManager()
        let timer = manager.createAndStartTimer(name: "Test", duration: 5, type: .seconds)
        timer.hasCompleted = true
        timer.isRunning = false
        timer.remainingTime = 0
        timer.endTime = Date().addingTimeInterval(-30)

        manager.addTime(id: timer.id, minutes: 1)

        XCTAssertGreaterThanOrEqual(timer.endTime!.timeIntervalSinceNow, 55)
        XCTAssertTrue(timer.isRunning)
    }

    func testAddTimeExtendsByFiveMinutes() throws {
        let manager = try makeTimerManager()
        let timer = manager.createAndStartTimer(name: "Test", duration: 5, type: .seconds)
        timer.hasCompleted = true
        timer.isRunning = false
        timer.remainingTime = 0

        manager.addTime(id: timer.id, minutes: 5)

        XCTAssertEqual(timer.endTime!.timeIntervalSinceNow, 300, accuracy: 2)
        XCTAssertGreaterThanOrEqual(timer.remainingTime ?? 0, 295)
    }

    func testDeleteTimerRemovesFromActiveTimers() throws {
        let manager = try makeTimerManager()
        let timer = manager.createAndStartTimer(name: "Delete me", duration: 10, type: .seconds)
        let id = timer.id

        manager.deleteTimer(id: id)

        XCTAssertFalse(manager.activeTimers.contains { $0.id == id })
    }

    func testNotificationActionIdentifiersRegisteredInSource() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RecipeScalerNative/Services/TimerManager.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("ADD_ONE_MINUTE"))
        XCTAssertTrue(source.contains("ADD_FIVE_MINUTES"))
        XCTAssertTrue(source.contains("DELETE_TIMER"))
        XCTAssertFalse(source.contains("SNOOZE_ACTION"))
        XCTAssertFalse(source.contains("snoozeTimer"))
    }
}
