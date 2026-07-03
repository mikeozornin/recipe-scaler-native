import GRDB
import XCTest
@testable import RecipeScalerNative

final class YjsWireSnapshotStoreTests: XCTestCase {
    func testSaveLoadDeleteWireSnapshot() async throws {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        let docKey = "user:recipe:test"
        let payload = Data([1, 2, 3, 4])
        try await store.saveYjsWireSnapshot(docKey: docKey, state: payload)
        let loaded = try await store.loadYjsWireSnapshot(docKey: docKey)
        XCTAssertEqual(loaded?.state, payload)
        try await store.deleteYjsWireSnapshot(docKey: docKey)
        let afterDelete = try await store.loadYjsWireSnapshot(docKey: docKey)
        XCTAssertNil(afterDelete)
    }

    func testLoadSnapshotsBatch() async throws {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        let keyA = "user:recipe:a"
        let keyB = "user:recipe:b"
        let stateA = Data([1, 2])
        let stateB = Data([3, 4])
        try await store.saveSnapshot(docKey: keyA, state: stateA, lastSyncedAt: nil)
        try await store.saveSnapshot(docKey: keyB, state: stateB, lastSyncedAt: nil)

        let loaded = try await store.loadSnapshots(docKeys: [keyA, keyB, "user:recipe:missing"])
        XCTAssertEqual(loaded[keyA]?.state, stateA)
        XCTAssertEqual(loaded[keyB]?.state, stateB)
        XCTAssertNil(loaded["user:recipe:missing"])
    }

    func testExistingSnapshotKeys() async throws {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        let keyA = "user:recipe:a"
        try await store.saveSnapshot(docKey: keyA, state: Data([1]), lastSyncedAt: nil)

        let existing = try await store.existingSnapshotKeys(docKeys: [keyA, "user:recipe:b"])
        XCTAssertEqual(existing, Set([keyA]))
    }

    func testLoadYjsWireSnapshotsBatch() async throws {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        let keyA = "user:recipe:a"
        let keyB = "user:recipe:b"
        let stateA = Data([5, 6])
        let stateB = Data([7, 8])
        try await store.saveYjsWireSnapshot(docKey: keyA, state: stateA)
        try await store.saveYjsWireSnapshot(docKey: keyB, state: stateB)

        let loaded = try await store.loadYjsWireSnapshots(docKeys: [keyA, keyB])
        XCTAssertEqual(loaded[keyA]?.state, stateA)
        XCTAssertEqual(loaded[keyB]?.state, stateB)
    }
}

final class YjsMergeHelperTests: XCTestCase {
    @MainActor
    func testMergeUpdatesSinglePartReturnsSameBytes() async throws {
        let part = Data([2, 1, 0])
        let merged = try await YjsMergeHelper.shared.mergeUpdates([part])
        XCTAssertEqual(merged, part)
    }
}

/// Scenario B regression: an offline local edit must survive a concurrent server edit
/// (CRDT merge, not last-writer clobber). This pins down open question #1 from
/// `offline-sync-issue.md` at the yrs engine level, with no device / WebView required.
final class YrsServerMergeTests: XCTestCase {
    private func makeManager() throws -> (DocumentManager, YDocStore) {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        return (DocumentManager(store: store), store)
    }

    func testServerUpdateMergesWithLocalEditsInsteadOfClobbering() async throws {
        let userId = "merge-user"

        // Replica A ("phone"): owns the base recipe.
        let (local, _) = try makeManager()
        await local.setUserId(userId)
        let recipeId = try await local.createRecipe(name: "Base")
        let key = "\(userId):recipe:\(recipeId)"
        let baseState = try await local.recipeDocumentState(recipeId: recipeId)

        // Replica B ("web"/server): seeded from the same base, makes a concurrent edit
        // (servings) while replica A is offline.
        let (remote, remoteStore) = try makeManager()
        await remote.setUserId(userId)
        try await remoteStore.saveSnapshot(docKey: key, state: baseState, lastSyncedAt: nil)
        _ = try await remote.getOrCreateDoc(key: key)
        try await remote.updateRecipeServings(recipeId: recipeId, servings: 7)
        let remoteFull = try await remote.recipeDocumentState(recipeId: recipeId)

        // Concurrent offline edit on replica A (different field — name).
        try await local.updateRecipeName(recipeId: recipeId, name: "Local Name")

        // Reconnect: merge the server state into local (the `applyServerDocumentState` path).
        try await local.applyUpdate(key: key, data: remoteFull)

        let merged = try await local.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(merged?.name, "Local Name", "offline local edit must survive the server merge")
        XCTAssertEqual(merged?.servings, 7, "concurrent server edit must be merged in, not clobbered")
    }
}

/// Regression for review finding #16 / plan 005:
/// a malformed Yjs update must not delete the SQLite snapshot, because that
/// snapshot may contain unsynced local edits. The fix evicts the in-memory doc
/// on apply failure but preserves the durable snapshot for recovery.
///
/// Note on test design: yrs FFI (`ytransaction_apply`) is not guaranteed to
/// throw deterministically on arbitrary bytes — it may silently no-op or, for
/// some malformed payloads, spin on varint parsing. To keep tests fast and
/// deterministic we drive the throw path through a tiny seam: a stored proc-
/// style `XCTestConfiguration`-friendly hook on `DocumentManager` that lets a
/// test force the next `applyUpdate`/`applyDescriptionEditorUpdate` to throw
/// `YrsError.applyFailed`. This is gated behind `#if DEBUG` and used only by
/// these tests; production code path is unchanged.
final class PreserveSnapshotOnApplyFailureTests: XCTestCase {
    private func makeManager() throws -> (DocumentManager, YDocStore) {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        return (DocumentManager(store: store), store)
    }

    func testApplyUpdateFailurePreservesSnapshot() async throws {
        let userId = "preserve-user"
        let (manager, store) = try makeManager()
        await manager.setUserId(userId)
        let recipeId = try await manager.createRecipe(name: "Recipe")
        let key = "\(userId):recipe:\(recipeId)"

        // Mutate to force a persisted snapshot containing unsynced local state.
        try await manager.updateRecipeName(recipeId: recipeId, name: "Edited Locally")
        let snapshotBefore = try await store.loadSnapshot(docKey: key)
        XCTAssertNotNil(snapshotBefore, "baseline snapshot must exist after a local edit")

        // Force the apply path to throw on the next call (test-only seam).
        await manager.setNextApplyUpdateShouldThrow()

        // Apply must throw via the catch path in applyUpdateToDoc.
        do {
            try await manager.applyUpdate(key: key, data: Data([0x00]))
            XCTFail("expected applyUpdate to throw when forced")
        } catch {
            // expected
        }

        // SQLite snapshot must be intact.
        let snapshotAfter = try await store.loadSnapshot(docKey: key)
        XCTAssertNotNil(snapshotAfter, "snapshot must NOT be deleted on apply failure")
        XCTAssertEqual(
            snapshotAfter?.state,
            snapshotBefore?.state,
            "snapshot bytes must be unchanged after apply failure"
        )

        // Recovery: next read rebuilds from the preserved snapshot, so the
        // local edit must still be visible.
        let recovered = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(
            recovered?.name,
            "Edited Locally",
            "local edit must survive apply failure via snapshot recovery"
        )
    }

    func testApplyDescriptionEditorUpdateFailurePreservesSnapshot() async throws {
        let userId = "preserve-desc-user"
        let (manager, store) = try makeManager()
        await manager.setUserId(userId)
        let recipeId = try await manager.createRecipe(name: "Recipe")
        let key = "\(userId):recipe:\(recipeId)"

        // Persist a baseline snapshot via a recipe mutation.
        try await manager.updateRecipeName(recipeId: recipeId, name: "Baseline")
        let snapshotBefore = try await store.loadSnapshot(docKey: key)
        XCTAssertNotNil(snapshotBefore, "baseline snapshot must exist after a local edit")

        // Force the apply path to throw on the next description editor update.
        await manager.setNextApplyUpdateShouldThrow()

        do {
            try await manager.applyDescriptionEditorUpdate(recipeId: recipeId, update: Data([0x00, 0x01]))
            XCTFail("expected applyDescriptionEditorUpdate to throw when forced")
        } catch {
            // expected
        }

        let snapshotAfter = try await store.loadSnapshot(docKey: key)
        XCTAssertNotNil(snapshotAfter, "snapshot must NOT be deleted on description editor apply failure")
        XCTAssertEqual(
            snapshotAfter?.state,
            snapshotBefore?.state,
            "snapshot bytes must be unchanged after description editor apply failure"
        )
    }
}

final class YjsPayloadBytesTests: XCTestCase {
    func testRoundTripUsingUInt8Array() {
        let original = Data([0, 1, 2, 255, 128, 42, 7])
        let array = YjsPayloadBytes.array(from: original)
        let restored = YjsPayloadBytes.data(from: array)
        XCTAssertEqual(restored, original)
    }

    func testRoundTripThroughNSNumber() {
        // Socket.IO JSON round-trips [UInt8] as [NSNumber]
        let original = Data([0, 1, 255, 42])
        let asNSNumbers: [NSNumber] = original.map { NSNumber(value: $0) }
        let restored = YjsPayloadBytes.data(from: asNSNumbers)
        XCTAssertEqual(restored, original)
    }

    func testRoundTripThroughIntArray() {
        // Backward compatibility: [Int] from web client
        let original = Data([0, 1, 255, 42])
        let asInts: [Int] = original.map { Int($0) }
        let restored = YjsPayloadBytes.data(from: asInts)
        XCTAssertEqual(restored, original)
    }
}

@MainActor
final class YjsOfflineOutboxTests: XCTestCase {
    private func makeSync() throws -> (YjsSyncService, YDocStore) {
        let store = try YDocStore.inMemory()
        let sync = YjsSyncService(store: store)
        return (sync, store)
    }

    func testDrainPreservesQueueWhenEmitFails() async throws {
        let (sync, store) = try makeSync()
        await sync.test_setUserIdForOfflineTests("outbox-user")
        let recipeId = "recipe-drain-fail"
        let docKey = sync.test_docKeyFor(recipeId: recipeId)
        let update = Data([2, 1, 0, 9, 8, 7])
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: update)

        await sync.test_drainOfflineQueue()

        let remaining = try await sync.test_offlineQueue.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.yjsUpdate, update)
        XCTAssertTrue(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)
    }

    func testSyncConfirmedDeletesOnlyInFlightBatch() async throws {
        let (sync, store) = try makeSync()
        await sync.test_setUserIdForOfflineTests("outbox-user")
        let recipeId = "recipe-ack-batch"
        let docKey = sync.test_docKeyFor(recipeId: recipeId)
        let updateA = Data([2, 1, 0, 1])
        let updateB = Data([2, 1, 0, 2])
        let updateC = Data([2, 1, 0, 3])
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: updateA)
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: updateB)
        let all = try await sync.test_offlineQueue.fetchAll()
        let idsAB = Set(all.compactMap(\.id))
        XCTAssertEqual(idsAB.count, 2)

        sync.test_markInFlightForTests(docKey: docKey, entryIds: idsAB)
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: updateC)

        await sync.test_handleSyncConfirmed(recipeId: recipeId, lastSyncedAt: nil)

        let after = try await sync.test_offlineQueue.fetchAll()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.yjsUpdate, updateC)
        XCTAssertTrue(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)
        XCTAssertTrue(sync.test_recipeHasQueuedWork(recipeId: recipeId))
    }

    func testStopClearsInFlightTracking() async throws {
        let (sync, _) = try makeSync()
        await sync.test_setUserIdForOfflineTests("outbox-user")
        let docKey = sync.test_docKeyFor(recipeId: "recipe-stop")
        sync.test_markInFlightForTests(docKey: docKey, entryIds: [1, 2])
        XCTAssertFalse(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)

        sync.stop()

        XCTAssertTrue(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)
    }

    func testReplaceOfflineQueueForRecipe() async throws {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        let docKey = "user:recipe:desc"
        let recipeId = "desc-recipe"
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: Data([1, 2]))
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: Data([3, 4]))
        let canonical = Data([2, 1, 0, 5, 6, 7, 8])
        try await store.replaceOfflineQueueForRecipe(
            docKey: docKey,
            recipeId: recipeId,
            yjsUpdate: canonical
        )
        let rows = try await store.fetchOfflineQueue()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.yjsUpdate, canonical)
        XCTAssertEqual(rows.first?.docKey, docKey)
    }

    func testSyncConfirmedWithNoInFlightDoesNotWipeQueue() async throws {
        let (sync, store) = try makeSync()
        await sync.test_setUserIdForOfflineTests("outbox-user")
        let recipeId = "recipe-live-confirm"
        let docKey = sync.test_docKeyFor(recipeId: recipeId)
        let update = Data([2, 1, 0, 4])
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: update)

        await sync.test_handleSyncConfirmed(recipeId: recipeId, lastSyncedAt: "2026-01-01T00:00:00Z")

        let remaining = try await sync.test_offlineQueue.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.yjsUpdate, update)
    }

    func testSyncConfirmedAcksCollectionOfflineBatch() async throws {
        let (sync, store) = try makeSync()
        let userId = "outbox-user"
        await sync.test_setUserIdForOfflineTests(userId)
        let recipeId = "collection"
        let docKey = "\(userId):collection"
        let update = Data([2, 1, 0, 10, 11])
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
        let rowId = try await sync.test_offlineQueue.fetchAll().first?.id
        XCTAssertNotNil(rowId)
        sync.test_markInFlightForTests(docKey: docKey, entryIds: Set([rowId!]))

        await sync.test_handleSyncConfirmed(recipeId: recipeId, lastSyncedAt: nil)

        let after = try await sync.test_offlineQueue.fetchAll()
        XCTAssertTrue(after.isEmpty)
        XCTAssertTrue(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)
    }

    func testReplaceForRecipeClearsInFlightTracking() async throws {
        let (sync, store) = try makeSync()
        await sync.test_setUserIdForOfflineTests("outbox-user")
        let recipeId = "recipe-replace-inflight"
        let docKey = sync.test_docKeyFor(recipeId: recipeId)
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: Data([1, 2]))
        let id = try await sync.test_offlineQueue.fetchAll().first?.id
        XCTAssertNotNil(id)
        sync.test_markInFlightForTests(docKey: docKey, entryIds: Set([id!]))

        let canonical = Data([2, 1, 0, 99])
        try await sync.test_offlineReplaceQueueAndClearInFlight(
            docKey: docKey,
            recipeId: recipeId,
            canonicalUpdate: canonical
        )

        XCTAssertTrue(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)
        let rows = try await sync.test_offlineQueue.fetchAll()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.yjsUpdate, canonical)
        await sync.test_drainOfflineQueue()
        XCTAssertTrue(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)
        let afterDrain = try await sync.test_offlineQueue.fetchAll()
        XCTAssertEqual(afterDrain.count, 1)
    }

    func testInFlightTimeoutClearsTrackingForRetry() async throws {
        let (sync, _) = try makeSync()
        await sync.test_setUserIdForOfflineTests("outbox-user")
        let docKey = sync.test_docKeyFor(recipeId: "recipe-ttl")
        sync.test_markInFlightForTests(docKey: docKey, entryIds: [42])
        let stale = Date().addingTimeInterval(-31)
        sync.test_setInFlightStartedAtForTests(docKey: docKey, startedAt: stale)
        XCTAssertFalse(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)

        sync.test_expireInFlightOfflineBatchesIfNeeded()

        XCTAssertTrue(sync.test_inFlightEntryIds(forDocKey: docKey).isEmpty)
    }

    func testReplaceOfflineQueueForRecipePreservesOtherRecipes() async throws {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        let docKeyA = "user:recipe:a"
        let docKeyB = "user:recipe:b"
        try await store.enqueueOfflineUpdate(docKey: docKeyA, recipeId: "recipe-a", yjsUpdate: Data([1]))
        try await store.enqueueOfflineUpdate(docKey: docKeyB, recipeId: "recipe-b", yjsUpdate: Data([2]))
        try await store.replaceOfflineQueueForRecipe(
            docKey: docKeyA,
            recipeId: "recipe-a",
            yjsUpdate: Data([9])
        )
        let rows = try await store.fetchOfflineQueue()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.contains { $0.recipeId == "recipe-b" && $0.yjsUpdate == Data([2]) })
    }
}

private extension YrsDatabase {
    static func migrateForTests(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_ydoc_snapshots") { db in
            try db.create(table: "ydoc_snapshots") { t in
                t.column("docKey", .text).primaryKey()
                t.column("state", .blob).notNull()
                t.column("lastSyncedAt", .text)
                t.column("updatedAt", .text).notNull()
            }
        }
        migrator.registerMigration("v2_create_offline_sync_queue") { db in
            try db.create(table: "offline_sync_queue") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("docKey", .text).notNull()
                t.column("recipeId", .text).notNull()
                t.column("yjsUpdate", .blob).notNull()
                t.column("createdAt", .text).notNull()
                t.column("attemptCount", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v4_create_yjs_wire_snapshots") { db in
            try db.create(table: "yjs_wire_snapshots") { t in
                t.column("docKey", .text).primaryKey()
                t.column("state", .blob).notNull()
                t.column("updatedAt", .text).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }
}
