//
//  YrsDatabaseInitTests.swift
//  RecipeScalerNativeTests
//
//  Regression: fresh installs have no Application Support directory on first
//  launch. YrsDatabase must create it before opening the SQLite file, or
//  sqlite3_open_v2 fails with SQLITE_CANTOPEN and the app silently runs on
//  the in-memory fallback ("Локальное хранилище недоступно" banner) until a
//  restart — recipes edited in that first session were never persisted.
//

import XCTest
@testable import RecipeScalerNative

final class YrsDatabaseInitTests: XCTestCase {

    private var freshDir: URL!

    override func setUpWithError() throws {
        // Static process-wide flag: other suites (YDocStore.inMemory tests) set
        // it via makeInMemoryFallback(). Reset so this suite asserts only what
        // its own init calls did.
        YrsDatabase.dbInitFailed = false
        // Simulate a fresh install: the parent directory does NOT exist yet,
        // matching an untouched application container.
        freshDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yrsdb-init-tests-\(UUID().uuidString)", isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: freshDir.path),
            "Test setup must start with a non-existent directory"
        )
    }

    override func tearDownWithError() throws {
        YrsDatabase.dbInitFailed = false
        try? FileManager.default.removeItem(at: freshDir)
    }

    /// Positive invariant: on a missing directory, `YrsDatabase` creates the
    /// directory AND the on-disk database file, and does not fall back.
    func testInitCreatesMissingDirectoryAndOpensOnDiskDatabase() throws {
        let db = try YrsDatabase(directory: freshDir)

        let dbFile = freshDir.appendingPathComponent("ydoc_snapshots.sqlite")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dbFile.path),
            "SQLite database file must exist on disk after init in a fresh directory"
        )
        XCTAssertFalse(
            YrsDatabase.dbInitFailed,
            "Fresh-install init must not trip the in-memory fallback flag"
        )

        // The opened queue must be usable (migrations applied, writable).
        try db.dbQueue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO recipe_sync_state (userId, recipeId, unsynced) VALUES ('u', 'r', 0)")
        }
        let count = try db.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recipe_sync_state")
        }
        XCTAssertEqual(count, 1)
    }

    /// Second open on the same directory must succeed too (idempotence across
    /// launches — no WAL/lock regressions from the created directory).
    func testReopenOnSameDirectorySucceeds() throws {
        _ = try YrsDatabase(directory: freshDir)
        let db2 = try YrsDatabase(directory: freshDir)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: freshDir.appendingPathComponent("ydoc_snapshots.sqlite").path
        ))
        _ = db2
    }
}
