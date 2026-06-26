//
//  TimerOrderingTests.swift
//  RecipeScalerNativeTests
//

import XCTest
import RecipeScalerCore

final class TimerOrderingTests: XCTestCase {
    private struct Stub {
        let id: String
        let paused: Bool
        let remaining: Int
    }

    func testRunningBeforePaused() {
        let timers = [
            Stub(id: "paused", paused: true, remaining: 30),
            Stub(id: "running", paused: false, remaining: 300),
        ]
        let sorted = TimerOrdering.sortActive(
            timers,
            isPaused: { $0.paused },
            remainingSeconds: { stub, _ in stub.remaining }
        )
        XCTAssertEqual(sorted.map(\.id), ["running", "paused"])
    }

    func testAscendingRemainingAmongRunning() {
        let timers = [
            Stub(id: "later", paused: false, remaining: 300),
            Stub(id: "soon", paused: false, remaining: 30),
            Stub(id: "overdue", paused: false, remaining: -120),
        ]
        let sorted = TimerOrdering.sortActive(
            timers,
            isPaused: { $0.paused },
            remainingSeconds: { stub, _ in stub.remaining }
        )
        XCTAssertEqual(sorted.map(\.id), ["overdue", "soon", "later"])
    }
}
