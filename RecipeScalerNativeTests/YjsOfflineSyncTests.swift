import GRDB
import XCTest
import YrsC
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

    private func setString(_ doc: YrsDocument, key: String, _ value: String) async throws {
        try await doc.testWriteTransaction { _, txn in
            let map = YrsMap(branch: try XCTUnwrap(ytype_get(txn, "recipe")))
            map.insert(key: key, value: .string(value), txn: txn)
        }
    }

    private func readString(_ doc: YrsDocument, key: String) async throws -> String? {
        try await doc.testReadTransaction { _, txn in
            guard let branch = ytype_get(txn, "recipe") else { return nil }
            return YrsMap(branch: branch).scalarString(key: key, txn: txn)
        }
    }

    /// Base state (optionally padded to `padding` bytes) plus two local name deltas on top.
    private func makeBaseAndDeltas(padding: Int = 0) async throws -> (base: Data, deltas: [Data]) {
        let doc = try YrsDocument()
        await doc.ensureRootMap(named: "recipe")
        try await setString(doc, key: "name", "Base")
        if padding > 0 {
            try await setString(doc, key: "originalRecipe", String(repeating: "x", count: padding))
        }
        _ = await doc.consumePendingLocalUpdateParts()
        let encoded = await doc.testEncodeStateAsUpdate()
        let base = try XCTUnwrap(encoded)
        try await setString(doc, key: "name", "First")
        try await setString(doc, key: "name", "Second")
        let deltas = await doc.consumePendingLocalUpdateParts()
        XCTAssertEqual(deltas.count, 2)
        return (base, deltas)
    }

    @MainActor
    func testMergeUpdatesMergesDeltasThatReplayOnBase() async throws {
        let (base, deltas) = try await makeBaseAndDeltas()
        let merged = try await YjsMergeHelper.shared.mergeUpdates(deltas)

        let replica = try YrsDocument(state: base)
        try await replica.applyUpdate(merged)
        let name = try await readString(replica, key: "name")
        XCTAssertEqual(name, "Second")
    }

    @MainActor
    func testEncodeFullStateAppliesUpdatesOnBootstrap() async throws {
        let (base, deltas) = try await makeBaseAndDeltas()
        let full = try await YjsMergeHelper.shared.encodeFullState(bootstrap: base, updates: deltas)

        let restored = try YrsDocument(state: full)
        let name = try await readString(restored, key: "name")
        XCTAssertEqual(name, "Second")
    }

    /// The wire-snapshot refresh path hands a full document to the helper; a large one
    /// must round-trip intact.
    @MainActor
    func testEncodeFullStateRoundTripsLargeDocument() async throws {
        let (base, deltas) = try await makeBaseAndDeltas(padding: 400_000)
        XCTAssertGreaterThan(base.count, 400_000)

        let start = Date()
        let full = try await YjsMergeHelper.shared.encodeFullState(bootstrap: base, updates: deltas)
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        print("YjsMergeHelper encodeFullState(\(base.count) bytes) took \(elapsedMs) ms")

        let restored = try YrsDocument(state: full)
        let name = try await readString(restored, key: "name")
        XCTAssertEqual(name, "Second")
        let padding = try await readString(restored, key: "originalRecipe")
        XCTAssertEqual(padding?.count, 400_000)
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

    func testAcceptsRawDataBinaryFrame() {
        // New binary transport: server emits native Socket.IO binary frames
        // (`Buffer` → `Data` on iOS). `YjsPayloadBytes.data(from:)` must pass
        // raw `Data` through untouched so the migration from JSON number
        // arrays is wire-compatible.
        let original = Data([0, 1, 2, 255, 128, 42, 7, 0xfe, 0xff])
        let restored = YjsPayloadBytes.data(from: original)
        XCTAssertEqual(restored, original)
    }

    func testAcceptsDoubleArray() {
        // Defensive: Socket.IO binary-as-JSON edge case where bytes surface as
        // `[Double]`. Truncation must recover the original byte values.
        let original = Data([0, 1, 255, 128, 42])
        let asDoubles: [Double] = original.map { Double($0) }
        let restored = YjsPayloadBytes.data(from: asDoubles)
        XCTAssertEqual(restored, original)
    }
}

@MainActor
final class SyncEventHandlerSyncStep2Tests: XCTestCase {
    func testParsesBinaryMissingUpdate() {
        let handler = SyncEventHandler()
        let missing = Data([0, 1, 2, 255, 42])
        var received: (String, Data, String?)?
        handler.onSyncStep2 = { recipeId, update, lastSyncedAt in
            received = (recipeId, update, lastSyncedAt)
        }

        handler.test_handleSyncStep2([[
            "recipeId": "recipe-abc",
            "missingUpdate": missing,
            "lastSyncedAt": "2026-08-08T00:00:00.000Z",
        ] as [String: Any]])

        XCTAssertEqual(received?.0, "recipe-abc")
        XCTAssertEqual(received?.1, missing)
        XCTAssertEqual(received?.2, "2026-08-08T00:00:00.000Z")
    }

    func testParsesLegacyNumberArrayMissingUpdate() {
        let handler = SyncEventHandler()
        let missing = Data([0, 1, 255, 128])
        var received: Data?
        handler.onSyncStep2 = { _, update, _ in
            received = update
        }

        let asInts: [Int] = missing.map { Int($0) }
        handler.test_handleSyncStep2([[
            "recipeId": "recipe-xyz",
            "missingUpdate": asInts,
        ] as [String: Any]])

        XCTAssertEqual(received, missing)
    }

    func testShoppingListDocumentKindMapsOfflineRecipeId() {
        let handler = SyncEventHandler()
        var receivedId: String?
        handler.onSyncStep2 = { recipeId, _, _ in
            receivedId = recipeId
        }

        handler.test_handleSyncStep2([[
            "documentKind": ShoppingListConstants.documentKind,
            "missingUpdate": Data([0, 0]),
        ] as [String: Any]])

        XCTAssertEqual(receivedId, ShoppingListConstants.offlineRecipeId)
    }

    func testOmittedRecipeIdMapsToCollection() {
        let handler = SyncEventHandler()
        var receivedId: String?
        handler.onSyncStep2 = { recipeId, _, _ in
            receivedId = recipeId
        }

        handler.test_handleSyncStep2([[
            "missingUpdate": Data([0, 0]),
        ] as [String: Any]])

        XCTAssertEqual(receivedId, "collection")
    }

    func testParsesCollectionSummaryFromSyncStep2() {
        let handler = SyncEventHandler()
        var receivedSummary: CollectionSyncSummary?
        var receivedRequestId: String?
        handler.onSyncStep2WithContext = { _, _, _, _, summary, requestId in
            receivedSummary = summary
            receivedRequestId = requestId
        }

        handler.test_handleSyncStep2([[
            "missingUpdate": Data([0, 0]),
            "requestId": "recovery-request-1",
            "collectionSummary": [
                "live": 2,
                "deleted": 1,
                "total": 3,
                "liveRecipeIds": ["recipe-a", "recipe-b"],
            ],
        ] as [String: Any]])

        XCTAssertEqual(receivedSummary?.liveCount, 2)
        XCTAssertEqual(receivedSummary?.deletedCount, 1)
        XCTAssertEqual(receivedSummary?.totalCount, 3)
        XCTAssertEqual(receivedSummary?.liveRecipeIds, Set(["recipe-a", "recipe-b"]))
        XCTAssertEqual(receivedRequestId, "recovery-request-1")
    }

    func testRejectsMalformedPresentCollectionSummaryInsteadOfTreatingItAsOmitted() {
        let handler = SyncEventHandler()
        var receivedSummary = false
        var receivedError: SyncErrorCode?
        handler.onSyncStep2WithContext = { _, _, _, _, _, _ in
            receivedSummary = true
        }
        handler.onSyncError = { _, code, _, recipeId in
            guard recipeId == "collection" else { return }
            receivedError = code
        }

        handler.test_handleSyncStep2([[
            "missingUpdate": Data([0, 0]),
            "collectionSummary": "not-an-object",
        ] as [String: Any]])

        XCTAssertFalse(receivedSummary)
        XCTAssertEqual(receivedError, .generic)
    }
}

@MainActor
final class YjsOfflineOutboxTests: XCTestCase {
    private func makeSync() throws -> (YjsSyncService, YDocStore) {
        let store = try YDocStore.inMemory()
        let sync = YjsSyncService.makeForTesting(store: store)
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

    /// Offline series of local deltas → reconnect drain must push every edit, not just the last.
    private func assertDrainPayloadCarriesAllOfflineEdits(withWireSnapshot: Bool) async throws {
        let (sync, store) = try makeSync()
        await sync.test_setUserIdForOfflineTests("outbox-user")
        let recipeId = "recipe-offline-series"
        let docKey = sync.test_docKeyFor(recipeId: recipeId)

        let doc = try YrsDocument()
        await doc.ensureRootMap(named: "recipe")
        func write(_ key: String, _ value: YrsInput) async throws {
            try await doc.testWriteTransaction { _, txn in
                YrsMap(branch: try XCTUnwrap(ytype_get(txn, "recipe"))).insert(key: key, value: value, txn: txn)
            }
        }
        try await write("name", .string("Base"))
        _ = await doc.consumePendingLocalUpdateParts()
        let encodedBase = await doc.testEncodeStateAsUpdate()
        let base = try XCTUnwrap(encodedBase)
        if withWireSnapshot {
            try await store.saveYjsWireSnapshot(docKey: docKey, state: base)
        }

        try await write("name", .string("Offline 1"))
        try await write("servings", .double(6))
        try await write("name", .string("Offline 2"))
        let deltas = await doc.consumePendingLocalUpdateParts()
        XCTAssertEqual(deltas.count, 3)
        for delta in deltas {
            try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: delta)
        }
        let encodedLocal = await doc.testEncodeStateAsUpdate()
        try await store.saveSnapshot(docKey: docKey, state: try XCTUnwrap(encodedLocal), lastSyncedAt: nil)

        let pushed = try await sync.test_resolveQueuedPushPayload(recipeId: recipeId)
        let server = try YrsDocument(state: base)
        try await server.applyUpdate(try XCTUnwrap(pushed))
        let (name, servings) = try await server.testReadTransaction { _, txn -> (String?, Double?) in
            guard let branch = ytype_get(txn, "recipe") else { return (nil, nil) }
            let map = YrsMap(branch: branch)
            return (map.scalarString(key: "name", txn: txn), map.double(key: "servings", txn: txn))
        }
        XCTAssertEqual(name, "Offline 2")
        XCTAssertEqual(servings, 6)
    }

    func testDrainPayloadCarriesAllOfflineEditsOnWireSnapshot() async throws {
        try await assertDrainPayloadCarriesAllOfflineEdits(withWireSnapshot: true)
    }

    func testDrainPayloadCarriesAllOfflineEditsWithoutWireSnapshot() async throws {
        try await assertDrainPayloadCarriesAllOfflineEdits(withWireSnapshot: false)
    }

    func testAccountScopedDocKeyDoesNotFollowCurrentAccount() async throws {
        let (sync, _) = try makeSync()
        await sync.test_setUserIdForOfflineTests("account-b")
        XCTAssertEqual(
            sync.test_docKeyFor(recipeId: "recipe-a", userId: "account-a"),
            "account-a:recipe:recipe-a"
        )
        XCTAssertNotEqual(
            sync.test_docKeyFor(recipeId: "recipe-a"),
            "account-a:recipe:recipe-a"
        )
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

    /// MIK-173: per-recipe fetch must not return other recipes' rows, and must preserve enqueue order.
    func testFetchOfflineQueueForRecipeIdFiltersAndOrders() async throws {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        let offline = OfflineWriteQueue(store: store)

        try await store.enqueueOfflineUpdate(docKey: "user:recipe:a", recipeId: "recipe-a", yjsUpdate: Data([1]))
        try await store.enqueueOfflineUpdate(docKey: "user:recipe:b", recipeId: "recipe-b", yjsUpdate: Data([2]))
        try await store.enqueueOfflineUpdate(docKey: "user:recipe:a", recipeId: "recipe-a", yjsUpdate: Data([3]))

        let forA = try await offline.fetch(forRecipeId: "recipe-a")
        XCTAssertEqual(forA.map(\.yjsUpdate), [Data([1]), Data([3])])
        XCTAssertTrue(forA.allSatisfy { $0.recipeId == "recipe-a" })

        let forB = try await offline.fetch(forRecipeId: "recipe-b")
        XCTAssertEqual(forB.map(\.yjsUpdate), [Data([2])])

        let missing = try await offline.fetch(forRecipeId: "recipe-missing")
        XCTAssertTrue(missing.isEmpty)
    }
}

/// Session-isolation regression tests for the Harden Yjs Sync plan.
///
/// These tests exercise the immutable `(sessionId, userId, client)` context
/// without a live socket: a DEBUG-only test seam fakes an authenticated
/// session, and stale vs current behavior is observed via the same handler
/// entry points Socket.IO would call.
@MainActor
final class YjsSessionIsolationTests: XCTestCase {
    private func makeSync() throws -> YjsSyncService {
        let store = try YDocStore.inMemory()
        return YjsSyncService.makeForTesting(store: store)
    }

    // MARK: - Stale `sync_step2` cannot modify the current account

    func testStaleSyncStep2FromPreviousAccountDoesNotApply() async throws {
        let sync = try makeSync()
        let accountA = sync.test_simulateAuthenticatedSession(userId: "account-a")
        let accountB = sync.test_simulateAuthenticatedSession(userId: "account-b")

        // A stale collection response from account A arrives after rotation.
        // Handler must reject it because the context is no longer current.
        let summary = CollectionSyncSummary(
            liveCount: 1,
            deletedCount: 0,
            totalCount: 1,
            liveRecipeIds: ["recipe-a"]
        )
        await sync.test_invokeSyncStep2(
            context: accountA,
            recipeId: "collection",
            missingUpdate: Data([0, 0]),
            collectionSummary: summary
        )

        // Account B must remain current; A must not have mutated state.
        XCTAssertFalse(sync.test_isCurrentSession(accountA))
        XCTAssertTrue(sync.test_isCurrentSession(accountB))
        XCTAssertEqual(sync.currentUserId, "account-b")
        // Stale response must not have been able to mark the gate ready.
        XCTAssertNotEqual(sync.test_collectionHandshakeState, "ready")
    }

    // MARK: - Same-account reconnect keeps the session current

    func testSameAccountReconnectProducesDistinctButOwnedSession() async throws {
        let sync = try makeSync()
        let first = sync.test_simulateAuthenticatedSession(userId: "user-x")
        XCTAssertTrue(sync.test_isCurrentSession(first))

        // A reconnect for the same account creates a different session.
        let second = sync.test_simulateAuthenticatedSession(userId: "user-x")
        XCTAssertFalse(sync.test_isCurrentSession(first))
        XCTAssertTrue(sync.test_isCurrentSession(second))
        XCTAssertEqual(first.userId, second.userId)
        XCTAssertNotEqual(first.sessionId, second.sessionId)
    }

    // MARK: - Collection gate blocks writes until handshake is ready

    func testCollectionGateBlocksDrainBeforeHandshakeReady() async throws {
        let sync = try makeSync()
        _ = sync.test_simulateAuthenticatedSession(userId: "user-c")
        let collectionDocKey = sync.test_docKeyFor(recipeId: "collection", userId: "user-c")
        try await sync.test_offlineQueue.enqueue(
            docKey: collectionDocKey,
            recipeId: "collection",
            yjsUpdate: Data([2, 1, 0, 5])
        )

        // Gate is still `idle`/`handshaking` after authentication; collection
        // writes must be skipped, not emitted.
        XCTAssertFalse(sync.test_canSendCollectionSync())
        await sync.test_drainOfflineQueue()

        let remaining = try await sync.test_offlineQueue.fetchAll()
        XCTAssertTrue(remaining.contains { $0.recipeId == "collection" })
    }

    // MARK: - Healthy handshake marks collection ready

    func testHealthyHandshakeMarksCollectionReady() async throws {
        let sync = try makeSync()
        let context = sync.test_simulateAuthenticatedSession(userId: "user-h")

        // Empty local + empty canonical summary → no truncation → gate ready.
        let summary = CollectionSyncSummary(
            liveCount: 0,
            deletedCount: 0,
            totalCount: 0,
            liveRecipeIds: []
        )
        await sync.test_invokeSyncStep2(
            context: context,
            recipeId: "collection",
            missingUpdate: Data([0, 0]),
            collectionSummary: summary
        )

        XCTAssertEqual(sync.test_collectionHandshakeState, "ready")
        XCTAssertTrue(sync.test_canSendCollectionSync())
    }

    // MARK: - Truncation triggers recovery

    func testMissingCanonicalLiveIdTriggersRecovery() async throws {
        let sync = try makeSync()
        let context = sync.test_simulateAuthenticatedSession(userId: "user-t")

        // Make `collectionIsTruncated` deterministically report truncation by
        // stubbing the local structure via the DEBUG fixture hook.
        let collectionDocKey = sync.test_docKeyFor(recipeId: "collection", userId: "user-t")
        try await sync.test_overwriteCollectionStructureForTests(
            docKey: collectionDocKey,
            structure: .init(liveRecipeIds: ["recipe-survivor"], deletedRecipeIds: [])
        )
        sync.test_setCollectionHandshakeReady()

        let summary = CollectionSyncSummary(
            liveCount: 2,
            deletedCount: 0,
            totalCount: 2,
            liveRecipeIds: ["recipe-survivor", "recipe-missing"]
        )
        await sync.test_invokeSyncStep2(
            context: context,
            recipeId: "collection",
            missingUpdate: Data([0, 0]),
            collectionSummary: summary
        )

        XCTAssertEqual(sync.test_collectionHandshakeState, "recovering")
        XCTAssertFalse(sync.test_canSendCollectionSync())
    }

    func testLateCollectionSyncStep2WithWrongRequestIdDoesNotCompleteRecovery() async throws {
        let sync = try makeSync()
        let context = sync.test_simulateAuthenticatedSession(userId: "user-correlation")
        let collectionDocKey = sync.test_docKeyFor(recipeId: "collection", userId: "user-correlation")
        try await sync.test_overwriteCollectionStructureForTests(
            docKey: collectionDocKey,
            structure: .init(liveRecipeIds: [], deletedRecipeIds: [])
        )
        sync.test_setCollectionRecoveryAwaitingResponse(requestId: "recovery-current")

        let summary = CollectionSyncSummary(
            liveCount: 0,
            deletedCount: 0,
            totalCount: 0,
            liveRecipeIds: []
        )
        await sync.test_invokeSyncStep2(
            context: context,
            recipeId: "collection",
            missingUpdate: Data([0, 0]),
            collectionSummary: summary,
            requestId: "recovery-stale"
        )

        XCTAssertEqual(sync.test_collectionHandshakeState, "recovering")
        XCTAssertFalse(sync.test_canSendCollectionSync())

        await sync.test_invokeSyncStep2(
            context: context,
            recipeId: "collection",
            missingUpdate: Data([0, 0]),
            collectionSummary: summary,
            requestId: "recovery-current"
        )

        XCTAssertEqual(sync.test_collectionHandshakeState, "ready")
    }

    // MARK: - Tombstone does not trigger recovery

    func testTombstoneDoesNotTriggerRecovery() async throws {
        let sync = try makeSync()
        let context = sync.test_simulateAuthenticatedSession(userId: "user-ts")

        let collectionDocKey = sync.test_docKeyFor(recipeId: "collection", userId: "user-ts")
        try await sync.test_overwriteCollectionStructureForTests(
            docKey: collectionDocKey,
            structure: .init(
                liveRecipeIds: ["recipe-live"],
                deletedRecipeIds: ["recipe-tombstoned"]
            )
        )
        sync.test_setCollectionHandshakeReady()

        let summary = CollectionSyncSummary(
            liveCount: 1,
            deletedCount: 1,
            totalCount: 2,
            liveRecipeIds: ["recipe-live"]
        )
        await sync.test_invokeSyncStep2(
            context: context,
            recipeId: "collection",
            missingUpdate: Data([0, 0]),
            collectionSummary: summary
        )

        // Tombstone is physically present, so no recovery; gate flips to ready.
        XCTAssertEqual(sync.test_collectionHandshakeState, "ready")
    }

    // MARK: - Recipe queue rows are unaffected by collection gating

    func testRecipeQueueSurvivesCollectionGate() async throws {
        let sync = try makeSync()
        _ = sync.test_simulateAuthenticatedSession(userId: "user-r")
        let recipeDocKey = sync.test_docKeyFor(recipeId: "recipe-r", userId: "user-r")
        let recipeUpdate = Data([2, 1, 0, 9])

        try await sync.test_offlineQueue.enqueue(
            docKey: recipeDocKey,
            recipeId: "recipe-r",
            yjsUpdate: recipeUpdate
        )
        // Collection gate is still closed, but the recipe row must persist.
        XCTAssertFalse(sync.test_canSendCollectionSync())

        let rows = try await sync.test_offlineQueue.fetchAll()
        XCTAssertTrue(rows.contains { $0.recipeId == "recipe-r" })
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

/// Perf review 2026-10-09 №1: a local edit must forward an incremental delta
/// (O(change)), not the whole document, and that delta must reproduce the edit
/// on a replica that only has the pre-edit state (server `Y.applyUpdate` path).
final class LocalDeltaDeliveryTests: XCTestCase {
    private actor UpdateSink {
        private var updates: [(docKey: String, data: Data)] = []

        func append(docKey: String, data: Data) {
            updates.append((docKey, data))
        }

        func drain(docKey: String) -> [Data] {
            let matching = updates.filter { $0.docKey == docKey }.map(\.data)
            updates.removeAll { $0.docKey == docKey }
            return matching
        }

        func count(docKey: String) -> Int {
            updates.filter { $0.docKey == docKey }.count
        }
    }

    private func makeManager() throws -> (DocumentManager, YDocStore) {
        let queue = try DatabaseQueue()
        try YrsDatabase.migrateForTests(queue)
        let store = YDocStore(dbQueue: queue)
        return (DocumentManager(store: store), store)
    }

    private func waitForUpdates(_ sink: UpdateSink, docKey: String, file: StaticString = #filePath, line: UInt = #line) async throws -> [Data] {
        for _ in 0..<200 {
            if await sink.count(docKey: docKey) > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // Let any sibling deliveries from the same mutation land.
        try await Task.sleep(nanoseconds: 50_000_000)
        let updates = await sink.drain(docKey: docKey)
        XCTAssertFalse(updates.isEmpty, "expected a local update for \(docKey)", file: file, line: line)
        return updates
    }

    private func makeIngredients(_ count: Int) -> [IngredientData] {
        (0..<count).map { index in
            IngredientData(
                id: "ing-\(index)",
                name: "Ingredient number \(index) with a reasonably long name",
                amount: "\(index + 1)",
                originalAmount: "\(index + 1)",
                unit: "g",
                order: index + 1
            )
        }
    }

    func testRecipeEditForwardsDeltaThatReplaysOnBaseState() async throws {
        let userId = "delta-user"
        let (local, _) = try makeManager()
        await local.setUserId(userId)
        let sink = UpdateSink()
        await local.setLocalUpdateHandler { context, data in
            await sink.append(docKey: context.docKey, data: data)
        }

        let recipeId = try await local.createRecipe(name: "Base")
        let key = "\(userId):recipe:\(recipeId)"
        try await local.addIngredients(recipeId: recipeId, ingredients: makeIngredients(60))
        _ = try await waitForUpdates(sink, docKey: key)
        let baseState = try await local.recipeDocumentState(recipeId: recipeId)

        try await local.updateRecipeName(recipeId: recipeId, name: "Renamed")
        let deltas = try await waitForUpdates(sink, docKey: key)
        let deltaBytes = deltas.reduce(0) { $0 + $1.count }
        XCTAssertLessThan(
            deltaBytes * 10,
            baseState.count,
            "rename must send a delta, not the full document (\(deltaBytes) vs \(baseState.count) bytes)"
        )

        let (replica, replicaStore) = try makeManager()
        await replica.setUserId(userId)
        try await replicaStore.saveSnapshot(docKey: key, state: baseState, lastSyncedAt: nil)
        _ = try await replica.getOrCreateDoc(key: key)
        for delta in deltas {
            try await replica.applyUpdate(key: key, data: delta)
        }
        let replayed = try await replica.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(replayed?.name, "Renamed")
        XCTAssertEqual(replayed?.ingredients.count, 60)
    }

    func testCollectionPinForwardsDeltaThatReplaysOnBaseState() async throws {
        let userId = "delta-collection-user"
        let (local, _) = try makeManager()
        await local.setUserId(userId)
        let sink = UpdateSink()
        await local.setLocalUpdateHandler { context, data in
            await sink.append(docKey: context.docKey, data: data)
        }
        let collectionKey = "\(userId):collection"

        var recipeIds: [String] = []
        for index in 0..<40 {
            recipeIds.append(try await local.createRecipe(name: "Recipe \(index)"))
        }
        _ = try await waitForUpdates(sink, docKey: collectionKey)
        let collectionDoc = try await local.getOrCreateDoc(key: collectionKey)
        let encodedBase = await collectionDoc.testEncodeStateAsUpdate()
        let baseState = try XCTUnwrap(encodedBase)

        let pinnedId = recipeIds[17]
        try await local.setCollectionEntryPinned(recipeId: pinnedId, isPinned: true)
        let deltas = try await waitForUpdates(sink, docKey: collectionKey)
        let deltaBytes = deltas.reduce(0) { $0 + $1.count }
        XCTAssertLessThan(
            deltaBytes * 10,
            baseState.count,
            "pin must send a delta, not the full collection (\(deltaBytes) vs \(baseState.count) bytes)"
        )

        let (replica, replicaStore) = try makeManager()
        await replica.setUserId(userId)
        try await replicaStore.saveSnapshot(docKey: collectionKey, state: baseState, lastSyncedAt: nil)
        _ = try await replica.getOrCreateDoc(key: collectionKey)
        for delta in deltas {
            try await replica.applyUpdate(key: collectionKey, data: delta)
        }
        let entries = try await replica.readCollectionEntries()
        XCTAssertEqual(entries.count, 40)
        XCTAssertEqual(entries.first { $0.id == pinnedId }?.isPinned, true)
        XCTAssertEqual(entries.filter(\.isPinned).count, 1)
    }

    func testEditPersistsSnapshotImmediately() async throws {
        let userId = "delta-persist-user"
        let (local, store) = try makeManager()
        await local.setUserId(userId)
        let recipeId = try await local.createRecipe(name: "Base")
        let key = "\(userId):recipe:\(recipeId)"
        try await local.updateRecipeName(recipeId: recipeId, name: "Persisted")

        let loaded = try await store.loadSnapshot(docKey: key)
        let snapshot = try XCTUnwrap(loaded)
        let (reader, readerStore) = try makeManager()
        await reader.setUserId(userId)
        try await readerStore.saveSnapshot(docKey: key, state: snapshot.state, lastSyncedAt: nil)
        let restored = try await reader.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(restored?.name, "Persisted")
    }
}

/// Pending local deltas must survive remote applies and description-editor
/// applies; before deltas were sent, `applyUpdate` silently cleared them.
final class YrsPendingLocalUpdateTests: XCTestCase {
    private func setName(_ doc: YrsDocument, _ name: String) async throws {
        try await doc.testWriteTransaction { _, txn in
            let map = YrsMap(branch: try XCTUnwrap(ytype_get(txn, "recipe")))
            map.insert(key: "name", value: .string(name), txn: txn)
        }
    }

    private func setServings(_ doc: YrsDocument, _ servings: Double) async throws {
        try await doc.testWriteTransaction { _, txn in
            let map = YrsMap(branch: try XCTUnwrap(ytype_get(txn, "recipe")))
            map.insert(key: "servings", value: .double(servings), txn: txn)
        }
    }

    private func readName(_ doc: YrsDocument) async throws -> String? {
        try await doc.testReadTransaction { _, txn in
            guard let branch = ytype_get(txn, "recipe") else { return nil }
            return YrsMap(branch: branch).scalarString(key: "name", txn: txn)
        }
    }

    private func makeBase() async throws -> (YrsDocument, Data) {
        let doc = try YrsDocument()
        await doc.ensureRootMap(named: "recipe")
        try await setName(doc, "Base")
        _ = await doc.consumePendingLocalUpdateParts()
        let encoded = await doc.testEncodeStateAsUpdate()
        let base = try XCTUnwrap(encoded)
        return (doc, base)
    }

    private func remoteServingsUpdate(base: Data) async throws -> Data {
        let remote = try YrsDocument(state: base)
        try await setServings(remote, 4)
        let parts = await remote.consumePendingLocalUpdateParts()
        return try XCTUnwrap(parts.first)
    }

    func testRemoteApplyKeepsPendingLocalDelta() async throws {
        let (doc, base) = try await makeBase()
        try await setName(doc, "Local")
        try await doc.applyUpdate(try await remoteServingsUpdate(base: base))

        let parts = await doc.consumePendingLocalUpdateParts()
        XCTAssertEqual(parts.count, 1, "remote apply must neither drop nor capture local deltas")
        let replica = try YrsDocument(state: base)
        for part in parts { try await replica.applyUpdate(part) }
        let name = try await readName(replica)
        XCTAssertEqual(name, "Local")
    }

    func testDescriptionLocalApplyIsNotCapturedAndKeepsPendingDelta() async throws {
        let (doc, base) = try await makeBase()
        try await setName(doc, "Local")
        try await doc.applyLocalUpdate(try await remoteServingsUpdate(base: base))

        let parts = await doc.consumePendingLocalUpdateParts()
        XCTAssertEqual(parts.count, 1, "forwarded editor bytes are sent by the caller, not re-captured")
        let replica = try YrsDocument(state: base)
        for part in parts { try await replica.applyUpdate(part) }
        let name = try await readName(replica)
        XCTAssertEqual(name, "Local")
    }

    func testSequentialTransactionsReplayInOrder() async throws {
        let (doc, base) = try await makeBase()
        try await setName(doc, "First")
        try await setName(doc, "Second")

        let parts = await doc.consumePendingLocalUpdateParts()
        XCTAssertEqual(parts.count, 2)
        let replica = try YrsDocument(state: base)
        for part in parts { try await replica.applyUpdate(part) }
        let name = try await readName(replica)
        XCTAssertEqual(name, "Second")
    }
}

/// A recipe peeked before it was ever downloaded (Spotlight / search) must not be
/// persisted as an empty snapshot that later counts as "cached locally".
final class EmptySnapshotPersistTests: XCTestCase {
    func testPeekedMissingRecipeIsNotReportedAsLocalSnapshot() async throws {
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId("u-empty")
        let key = "u-empty:recipe:never-downloaded"

        _ = try await manager.getOrCreateDoc(key: key)
        await manager.persistAll()

        let existing = try await store.existingSnapshotKeys(docKeys: [key])
        XCTAssertFalse(existing.contains(key), "empty doc must not mark the recipe as cached")
    }

    func testLegacyEmptySnapshotRowIsIgnoredButRealSnapshotCounts() async throws {
        let store = try YDocStore.inMemory()
        let legacyKey = "u-empty:recipe:legacy-empty"
        try await store.saveLocalSnapshot(docKey: legacyKey, state: Data([0, 0]))

        let manager = DocumentManager(store: store)
        await manager.setUserId("u-empty")
        let recipeId = try await manager.createRecipe(name: "Борщ 🍲")
        let realKey = "u-empty:recipe:\(recipeId)"
        await manager.persistAll()

        let existing = try await store.existingSnapshotKeys(docKeys: [legacyKey, realKey])
        XCTAssertEqual(existing, [realKey])
    }
}

/// Reconnect must not read every recipe snapshot / probe the queue per recipe
/// when nothing is unsynced (review 2026.10.09 appendix, sync №2).
@MainActor
final class ReconnectSnapshotLoadTests: XCTestCase {
    private final class SQLLog: @unchecked Sendable {
        private let lock = NSLock()
        private var statements: [String] = []
        /// GRDB quotes identifiers (`FROM "ydoc_snapshots"`); strip quotes so fragments stay readable.
        func append(_ sql: String) {
            let unquoted = sql.replacingOccurrences(of: "\"", with: "")
            lock.lock(); statements.append(unquoted); lock.unlock()
        }
        func reset() { lock.lock(); statements.removeAll(); lock.unlock() }
        func matching(_ fragment: String) -> [String] {
            lock.lock(); defer { lock.unlock() }
            return statements.filter { $0.contains(fragment) }
        }
    }

    private func makeTracedStore() throws -> (YDocStore, SQLLog) {
        let log = SQLLog()
        var config = Configuration()
        config.prepareDatabase { db in
            db.trace(options: .statement) { event in log.append(event.expandedDescription) }
        }
        let queue = try DatabaseQueue(configuration: config)
        try YrsDatabase.migrateForTests(queue)
        return (YDocStore(dbQueue: queue), log)
    }

    func testRefreshWireSnapshotsSkipsSnapshotReadsWhenNothingIsUnsynced() async throws {
        let (store, log) = try makeTracedStore()
        let userId = "u-reconnect"
        let recipeIds = (0..<30).map { "r\($0)" }
        for recipeId in recipeIds {
            try await store.saveSnapshot(
                docKey: "\(userId):recipe:\(recipeId)",
                state: Data(repeating: 7, count: 4096),
                lastSyncedAt: "2026-10-10T00:00:00Z"
            )
        }
        let sync = YjsSyncService.makeForTesting(store: store)
        await sync.test_setUserIdForOfflineTests(userId)
        log.reset()

        await sync.test_refreshWireSnapshotsForRecipes(recipeIds: recipeIds)

        XCTAssertEqual(log.matching("FROM ydoc_snapshots"), [], "no unsynced recipes → no yrs snapshot reads")
        XCTAssertEqual(log.matching("FROM yjs_wire_snapshots"), [], "no unsynced recipes → no wire snapshot reads")
    }

    func testRefreshWireSnapshotsLoadsOnlyUnsyncedRecipeAndStillWritesWireState() async throws {
        let (store, log) = try makeTracedStore()
        let userId = "u-reconnect"
        let author = DocumentManager(store: store)
        await author.setUserId(userId)
        var recipeIds: [String] = []
        for index in 0..<5 {
            recipeIds.append(try await author.createRecipe(name: "Рецепт \(index) 🍲"))
        }
        await author.persistAll()
        let dirtyId = recipeIds[3]
        let dirtyKey = "\(userId):recipe:\(dirtyId)"
        let dirtyState = try await author.recipeDocumentState(recipeId: dirtyId)
        try await store.enqueueOfflineUpdate(docKey: dirtyKey, recipeId: dirtyId, yjsUpdate: dirtyState)

        let sync = YjsSyncService.makeForTesting(store: store)
        await sync.test_setUserIdForOfflineTests(userId)
        log.reset()

        await sync.test_refreshWireSnapshotsForRecipes(recipeIds: recipeIds)

        let snapshotReads = log.matching("FROM ydoc_snapshots")
        XCTAssertFalse(snapshotReads.isEmpty)
        for cleanId in recipeIds where cleanId != dirtyId {
            XCTAssertFalse(
                snapshotReads.contains { $0.contains("\(userId):recipe:\(cleanId)") },
                "clean recipe \(cleanId) snapshot must not be read"
            )
        }
        let wire = try await store.loadYjsWireSnapshot(docKey: dirtyKey)
        XCTAssertGreaterThan(wire?.state.count ?? 0, 2, "unsynced recipe still gets its wire snapshot rebuilt")
    }

    func testOfflineDescriptionUpdatesDoNotRewriteSnapshotEachTimeButStayDurable() async throws {
        let (store, log) = try makeTracedStore()
        let userId = "u-offline-desc"
        let sync = YjsSyncService.makeForTesting(store: store)
        await sync.test_setUserIdForOfflineTests(userId)
        let recipeId = try await sync.createRecipe()
        await sync.loadRecipe(recipeId: recipeId)
        let docKey = "\(userId):recipe:\(recipeId)"

        // WebView stand-in: a second replica producing real Yjs updates.
        let editorStore = try YDocStore.inMemory()
        let bootstrap = try await sync.descriptionEditorBootstrap(recipeId: recipeId).state
        try await editorStore.saveSnapshot(docKey: docKey, state: bootstrap, lastSyncedAt: nil)
        let editor = DocumentManager(store: editorStore)
        await editor.setUserId(userId)
        _ = try await editor.getOrCreateDoc(key: docKey)
        log.reset()

        for index in 0..<10 {
            try await editor.updateRecipeName(recipeId: recipeId, name: "Офлайн \(index) ✏️")
            let update = try await editor.recipeDocumentState(recipeId: recipeId)
            try await sync.applyDescriptionEditorUpdate(recipeId: recipeId, update: update)
        }

        XCTAssertLessThanOrEqual(
            log.matching("INSERT INTO ydoc_snapshots").count,
            1,
            "offline editor updates must use the debounced snapshot, not a full write per update"
        )
        let queued = try await sync.test_offlineQueue.fetch(forRecipeId: recipeId)
        XCTAssertEqual(queued.count, 10, "every offline update is durably queued")

        // Killed before the debounce fired: launch replays the queue over the older snapshot.
        let relaunched = DocumentManager(store: store)
        await relaunched.setUserId(userId)
        await relaunched.applyOfflineQueueToLocalDocs(userId: userId)
        let recovered = try await relaunched.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(recovered?.name, "Офлайн 9 ✏️", "queue replay restores edits missing from the snapshot")

        await sync.flushPendingSnapshots()
        let reader = DocumentManager(store: store)
        await reader.setUserId(userId)
        let persisted = try await reader.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(persisted?.name, "Офлайн 9 ✏️", "flushed snapshot holds the latest offline edit")
    }

    func testDescriptionExportCheckQueriesOfflineQueueOnce() async throws {
        let (store, log) = try makeTracedStore()
        let userId = "u-reconnect"
        let recipeIds = (0..<30).map { "r\($0)" }
        let sync = YjsSyncService.makeForTesting(store: store)
        let context = sync.test_simulateAuthenticatedSession(userId: userId)
        await sync.test_setUserIdForOfflineTests(userId)
        log.reset()

        await sync.test_scheduleDescriptionWireExportIfNeeded(recipeIds: recipeIds, sessionContext: context)

        XCTAssertLessThanOrEqual(
            log.matching("FROM offline_sync_queue").count,
            1,
            "one queue read per reconnect, not one per recipe"
        )
    }
}
