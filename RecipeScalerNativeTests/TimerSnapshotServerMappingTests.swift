//
//  TimerSnapshotServerMappingTests.swift
//
//  Spec 030 Phase B3 — ServerActiveTimer → TimerSnapshot mapping + offline keep.
//

import XCTest
import RecipeScalerCore

final class TimerSnapshotServerMappingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testMapping_Running() {
        let endMs = Int64((now.timeIntervalSince1970 + 120) * 1000)
        let server = makeServer(
            timerId: "t1",
            name: "Boil",
            duration: 300,
            endTime: endMs,
            isPaused: false
        )
        let snap = TimerSnapshot(from: server, now: now)
        XCTAssertEqual(snap.phase, .running)
        XCTAssertNotNil(snap.endDate)
        XCTAssertNil(snap.pausedRemainingSeconds)
        XCTAssertEqual(snap.totalDurationSeconds, 300)
        XCTAssertEqual(snap.recipeName, nil)
    }

    func testMapping_Paused() {
        let endMs = Int64((now.timeIntervalSince1970 + 90) * 1000)
        let pausedAt = Int64(now.timeIntervalSince1970 * 1000)
        let server = makeServer(
            timerId: "t2",
            name: "Rest",
            duration: 180,
            endTime: endMs,
            isPaused: true,
            pausedAt: pausedAt
        )
        let snap = TimerSnapshot(from: server, now: now)
        XCTAssertEqual(snap.phase, .paused)
        XCTAssertNil(snap.endDate)
        XCTAssertEqual(snap.pausedRemainingSeconds, 90)
    }

    func testMapping_Exceeded() {
        let endMs = Int64((now.timeIntervalSince1970 - 30) * 1000)
        let server = makeServer(
            timerId: "t3",
            name: "Bake",
            duration: 600,
            endTime: endMs,
            isPaused: false
        )
        let snap = TimerSnapshot(from: server, now: now)
        XCTAssertEqual(snap.phase, .exceeded)
        XCTAssertNotNil(snap.endDate)
    }

    func testDocument_TopFourOrdering() {
        let servers = (0..<6).map { index -> ServerActiveTimer in
            let endMs = Int64((now.timeIntervalSince1970 + Double(600 - index * 10)) * 1000)
            return makeServer(
                timerId: "t\(index)",
                name: "T\(index)",
                duration: 600,
                endTime: endMs,
                isPaused: index == 5
            )
        }
        let doc = TimerSnapshotDocument(from: servers, now: now)
        XCTAssertEqual(doc.timers.count, 4)
        // Running timers first (index 5 is paused and should not be in top if 4 runners exist).
        XCTAssertFalse(doc.timers.contains(where: { $0.id == "t5" }))
    }

    func testNetworkRefresh_UpdatedOnSuccess() {
        let existing = TimerSnapshotDocument(
            timers: [
                TimerSnapshot(
                    id: "old",
                    name: "Old",
                    recipeId: nil,
                    recipeName: nil,
                    endDate: now.addingTimeInterval(60),
                    pausedRemainingSeconds: nil,
                    phase: .running,
                    totalDurationSeconds: 60
                )
            ],
            generatedAt: now.addingTimeInterval(-100)
        )
        let endMs = Int64((now.timeIntervalSince1970 + 45) * 1000)
        let fresh = [
            makeServer(timerId: "new", name: "New", duration: 90, endTime: endMs, isPaused: false)
        ]
        let outcome = TimerWidgetNetworkRefresh.apply(
            bearer: "tok",
            existing: existing,
            fetchResult: .success(fresh),
            now: now
        )
        guard case .updated(let doc) = outcome else {
            return XCTFail("expected updated")
        }
        XCTAssertEqual(doc.timers.count, 1)
        XCTAssertEqual(doc.timers[0].id, "new")
    }

    func testNetworkRefresh_PendingLocalBlocksOverwrite() {
        let existing = TimerSnapshotDocument(
            timers: [
                TimerSnapshot(
                    id: "local",
                    name: "Local",
                    recipeId: nil,
                    recipeName: nil,
                    endDate: nil,
                    pausedRemainingSeconds: 40,
                    phase: .paused,
                    totalDurationSeconds: 120
                )
            ],
            generatedAt: now
        )
        let endMs = Int64((now.timeIntervalSince1970 + 45) * 1000)
        let outcome = TimerWidgetNetworkRefresh.apply(
            bearer: "tok",
            existing: existing,
            fetchResult: .success([
                makeServer(timerId: "server", name: "Server", duration: 90, endTime: endMs, isPaused: false)
            ]),
            hasPendingLocal: true,
            now: now
        )
        guard case .skippedPendingLocal(let doc) = outcome else {
            return XCTFail("expected skippedPendingLocal")
        }
        XCTAssertEqual(doc.timers.map(\.id), ["local"])
    }

    func testShouldFetch_FalseWhenFreshOrPending() {
        let fresh = TimerSnapshotDocument(timers: [], generatedAt: now.addingTimeInterval(-10))
        XCTAssertFalse(
            TimerWidgetNetworkRefresh.shouldFetch(existing: fresh, hasPendingLocal: false, now: now)
        )
        let stale = TimerSnapshotDocument(timers: [], generatedAt: now.addingTimeInterval(-100))
        XCTAssertTrue(
            TimerWidgetNetworkRefresh.shouldFetch(existing: stale, hasPendingLocal: false, now: now)
        )
        XCTAssertFalse(
            TimerWidgetNetworkRefresh.shouldFetch(existing: stale, hasPendingLocal: true, now: now)
        )
    }

    func testNetworkRefresh_OfflineKeepsExisting() {
        let existing = TimerSnapshotDocument(
            timers: [
                TimerSnapshot(
                    id: "keep",
                    name: "Keep",
                    recipeId: nil,
                    recipeName: nil,
                    endDate: nil,
                    pausedRemainingSeconds: 40,
                    phase: .paused,
                    totalDurationSeconds: 120
                )
            ],
            generatedAt: now
        )
        let outcome = TimerWidgetNetworkRefresh.apply(
            bearer: "tok",
            existing: existing,
            fetchResult: .failure(URLError(.notConnectedToInternet)),
            now: now
        )
        guard case .keptExisting(let doc) = outcome else {
            return XCTFail("expected keptExisting")
        }
        XCTAssertEqual(doc.timers.map(\.id), ["keep"])
    }

    func testNetworkRefresh_NoAuthSkipsWithoutClear() {
        let existing = TimerSnapshotDocument(
            timers: [
                TimerSnapshot(
                    id: "keep",
                    name: "Keep",
                    recipeId: nil,
                    recipeName: nil,
                    endDate: now.addingTimeInterval(10),
                    pausedRemainingSeconds: nil,
                    phase: .running,
                    totalDurationSeconds: 10
                )
            ],
            generatedAt: now
        )
        let outcome = TimerWidgetNetworkRefresh.apply(
            bearer: nil,
            existing: existing,
            fetchResult: .success([]),
            now: now
        )
        guard case .skippedNoAuth(let doc) = outcome else {
            return XCTFail("expected skippedNoAuth")
        }
        XCTAssertEqual(doc.timers.map(\.id), ["keep"])
    }

    // MARK: - fixtures

    private func makeServer(
        timerId: String,
        name: String,
        duration: Int,
        endTime: Int64?,
        isPaused: Bool,
        pausedAt: Int64? = nil
    ) -> ServerActiveTimer {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        return ServerActiveTimer(
            timerId: timerId,
            name: name,
            duration: duration,
            endTime: endTime,
            isPaused: isPaused,
            pausedDuration: isPaused ? 10 : nil,
            createdAt: nowMs - 60_000,
            lastUpdated: nowMs,
            startedAt: nowMs - 30_000,
            pausedAt: pausedAt,
            recipeId: nil
        )
    }
}
