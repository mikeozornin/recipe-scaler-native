//
//  TimerSyncQueueTests.swift
//
//  Review 2026.09.04 №3 + №4 + №11 — outbound timer sync queue semantics.
//
//    1. №4: a timer created offline whose create-event POST failed must
//       survive a successful GET /active pull (no silent deletion).
//    2. №11: the POST-ack removal must only drop events that were actually
//       on the wire — events enqueued for the same timer while the POST was
//       in flight (pause → resume) must stay queued.
//    3. №3: `clearForLogout` wipes the persisted queue + in-memory state so
//       user A's pending events cannot reach the server as user B's ghosts.
//
//  The HTTP layer is indirected via the `activeTimersLoader` / `syncPoster`
//  test seams so no network is touched. TimerManager comes from the
//  in-memory AppContainer (project test pattern).
//

import XCTest
import RecipeScalerCore
import SwiftData
@testable import RecipeScalerNative

@MainActor
final class TimerSyncQueueTests: XCTestCase {
    private var service: TimerSyncService!
    private var manager: TimerManager!
    private var container: AppContainer?

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UserDefaults.standard.removeObject(forKey: "timer_sync_state")

        let modelContainer = try TestSupport.makeInMemoryContainer()
        let appContainer = try AppContainer(modelContext: ModelContext(modelContainer))
        container = appContainer
        manager = appContainer.timer
        manager.clearForLogout()

        service = TimerSyncService()
        service.configure(userId: "user-1", deviceId: "device-1", timerManager: manager)
    }

    override func tearDownWithError() throws {
        service.clearForLogout()
        service = nil
        UserDefaults.standard.removeObject(forKey: "timer_sync_state")
        manager = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - №11 — ack snapshot removes only sent events

    func testAckByTimerId_doesNotRemoveEventsEnqueuedMidFlight() async throws {
        let pauseEventId = await enqueueForTest(type: .timerPaused, timerId: "t1", payload: ["remaining": 60])
        XCTAssertEqual(service.pendingEventsForTesting.count, 1)

        service.syncPoster = { _ in
            // While the POST is in flight the user hits Resume.
            _ = await self.enqueueForTest(type: .timerResumed, timerId: "t1", payload: [:])
            return try Self.decodeSyncResponse(syncedEvents: ["t1"])
        }

        await service.flushPendingSyncImmediately()

        XCTAssertFalse(
            service.pendingEventsForTesting.contains { $0.id == pauseEventId },
            "The pause event was on the wire and acked — it must be removed"
        )
        XCTAssertTrue(
            service.pendingEventsForTesting.contains { $0.type == .timerResumed },
            "Resume was enqueued after the POST body was built — the timerId-only ack must not drop it (№11)"
        )
    }

    // MARK: - №4 — offline-created timers survive the pull

    func testLoadActiveTimers_preservesOfflineCreatedTimerWhenCreateWasNotSynced() async throws {
        // Timer created offline; the create POST fails (network error), the
        // GET /active pull succeeds and does not know the timer. The local
        // timer must survive `replaceTimersFromServer`.
        service.syncPoster = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let createdEventId = await enqueueForTest(type: .timerCreated, timerId: "offline-1", payload: [:])
        await service.flushPendingSyncImmediately()
        XCTAssertEqual(service.pendingEventsForTesting.count, 1)

        manager.upsertTimerFromSync(makeLocalTimer(id: "offline-1"))
        service.activeTimersLoader = {
            try Self.decodeActiveTimersResponse(json: #"{"success":true,"data":{"timers":[]}}"#)
        }

        await service.loadActiveTimersFromServer(force: true)

        XCTAssertTrue(
            manager.timers.contains { $0.id == "offline-1" },
            "Offline-created timer with unsynced create-event must survive the server pull (№4)"
        )
        XCTAssertTrue(
            service.pendingEventsForTesting.contains { $0.id == createdEventId },
            "The create-event is still unsynced — it must stay queued for retry"
        )
    }

    // MARK: - №3 — logout wipes the queue

    func testClearForLogout_wipesPersistedAndInMemoryQueue() async {
        _ = await enqueueForTest(type: .timerCreated, timerId: "t9", payload: [:])
        XCTAssertFalse(service.pendingEventsForTesting.isEmpty)

        service.clearForLogout()

        XCTAssertTrue(service.pendingEventsForTesting.isEmpty)
        XCTAssertNil(
            UserDefaults.standard.data(forKey: "timer_sync_state"),
            "The persisted queue must be removed so the next account starts clean (№3)"
        )
    }

    // MARK: - Helpers

    /// Enqueues an event over the real path and returns its generated id.
    /// Awaits one main-actor hop so the synchronous append lands first.
    private func enqueueForTest(
        type: SyncedTimerEventType,
        timerId: String,
        payload: [String: Any]
    ) async -> String {
        let idSnapshot = service.pendingEventsForTesting.map(\.id)
        service.enqueue(type: type, timerId: timerId, payload: payload)
        await Task.yield()
        let after = service.pendingEventsForTesting
        return after.map(\.id).first { !idSnapshot.contains($0) } ?? ""
    }

    private func makeLocalTimer(id: String) -> RecipeTimer {
        RecipeTimer(id: id, name: "Offline", duration: 300, type: .seconds)
    }

    /// `TimerSyncHTTPResponse` has no public memberwise init — build via JSON.
    private static func decodeSyncResponse(syncedEvents: [String]) throws -> TimerSyncHTTPResponse {
        let eventsJSON = syncedEvents
            .map { "\"\($0)\"" }
            .joined(separator: ",")
        let json = #"{"success":true,"data":{"syncedEvents":[\#(eventsJSON)]}}"#
        return try JSONDecoder().decode(TimerSyncHTTPResponse.self, from: Data(json.utf8))
    }

    private static func decodeActiveTimersResponse(json: String) throws -> ActiveTimersResponse {
        try JSONDecoder().decode(ActiveTimersResponse.self, from: Data(json.utf8))
    }
}
