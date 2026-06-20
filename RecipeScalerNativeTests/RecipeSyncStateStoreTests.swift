import GRDB
import XCTest
@testable import RecipeScalerNative

/// MIK-128: per-recipe sync flags (`unsynced`) moved from `UserDefaults.standard` into
/// the SQLite table `recipe_sync_state`. These tests pin down the v5 migration, the
/// CRUD API on `YDocStore`, and the fact that `deleteAll()` (used on logout) wipes the
/// new table alongside `ydoc_snapshots`.
final class RecipeSyncStateStoreTests: XCTestCase {

    private func makeStore() throws -> YDocStore {
        try YDocStore.inMemory()
    }

    // MARK: - Schema / migration v5

    func testMigrationV5CreatesRecipeSyncStateTable() throws {
        let store = try makeStore()
        let tableName = try store.test_tableName()
        XCTAssertEqual(tableName, "recipe_sync_state")
    }

    func testMigrationV5HasUnsyncedColumn() throws {
        let store = try makeStore()
        let columns = try store.test_columnsOfRecipeSyncState()
        XCTAssertEqual(columns, ["recipeId", "unsynced"])
    }

    // MARK: - Round-trip

    func testSetRecipeUnsyncedThenLoad() async throws {
        let store = try makeStore()
        try await store.setRecipeUnsynced(recipeId: "r1", unsynced: true)
        try await store.setRecipeUnsynced(recipeId: "r2", unsynced: true)
        try await store.setRecipeUnsynced(recipeId: "r3", unsynced: false)

        let unsynced = try await store.loadUnsyncedRecipeIds()
        XCTAssertEqual(unsynced, Set(["r1", "r2"]))
    }

    func testSetRecipeUnsyncedIsIdempotentUpsert() async throws {
        let store = try makeStore()
        try await store.setRecipeUnsynced(recipeId: "r1", unsynced: true)
        try await store.setRecipeUnsynced(recipeId: "r1", unsynced: true)

        let unsynced = try await store.loadUnsyncedRecipeIds()
        XCTAssertEqual(unsynced, Set(["r1"]))
    }

    func testSetRecipeUnsyncedThenClear() async throws {
        let store = try makeStore()
        try await store.setRecipeUnsynced(recipeId: "r1", unsynced: true)
        try await store.setRecipeUnsynced(recipeId: "r1", unsynced: false)

        let unsynced = try await store.loadUnsyncedRecipeIds()
        XCTAssertTrue(unsynced.isEmpty)
    }

    func testDeleteRecipeSyncState() async throws {
        let store = try makeStore()
        try await store.setRecipeUnsynced(recipeId: "r1", unsynced: true)
        try await store.deleteRecipeSyncState(recipeId: "r1")

        let unsynced = try await store.loadUnsyncedRecipeIds()
        XCTAssertTrue(unsynced.isEmpty)
    }

    // MARK: - Logout

    func testDeleteAllWipesRecipeSyncState() async throws {
        let store = try makeStore()
        try await store.setRecipeUnsynced(recipeId: "r1", unsynced: true)
        try await store.setRecipeUnsynced(recipeId: "r2", unsynced: true)

        try await store.deleteAll()

        let unsynced = try await store.loadUnsyncedRecipeIds()
        XCTAssertTrue(unsynced.isEmpty)
    }

    func testDeleteAllWipesSnapshotsAndSyncStateTogether() async throws {
        let store = try makeStore()
        let docKey = "user:recipe:r1"
        try await store.saveSnapshot(docKey: docKey, state: Data([1, 2, 3]), lastSyncedAt: nil)
        try await store.setRecipeUnsynced(recipeId: "r1", unsynced: true)

        try await store.deleteAll()

        let snapshot = try await store.loadSnapshot(docKey: docKey)
        XCTAssertNil(snapshot)
        let unsynced = try await store.loadUnsyncedRecipeIds()
        XCTAssertTrue(unsynced.isEmpty)
    }

    func testLoadUnsyncedRecipeIdsOnEmptyStore() async throws {
        let store = try makeStore()
        let unsynced = try await store.loadUnsyncedRecipeIds()
        XCTAssertTrue(unsynced.isEmpty)
    }
}

/// Backdoor helpers used only by `RecipeSyncStateStoreTests` to assert on schema shape.
/// Kept narrow on purpose — production code never introspects columns this way.
extension YDocStore {
    func test_tableName() throws -> String {
        try dbQueue.read { db in
            let cursor = try String.fetchCursor(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='recipe_sync_state'"
            )
            return try cursor.next() ?? ""
        }
    }

    func test_columnsOfRecipeSyncState() throws -> [String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(recipe_sync_state)")
            return rows.map { $0["name"] }
        }
    }
}
