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
        XCTAssertNil(try await store.loadYjsWireSnapshot(docKey: docKey))
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
