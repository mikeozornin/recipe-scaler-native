import Foundation
import GRDB


/// GRDB database setup and migration for Y.Doc snapshot storage.
///
/// Database file: `ApplicationSupport/ydoc_snapshots.sqlite`
/// Schema: single `ydoc_snapshots` table with WAL mode for concurrent reads.
final class YrsDatabase {
    let dbQueue: DatabaseQueue
    /// `true` when on-disk open failed and the app is using an in-memory fallback.
    static var dbInitFailed = false

    /// `directory` is injectable for tests; `nil` resolves to the app's
    /// Application Support (production path). The directory is created when
    /// missing because a fresh install has no Application Support and
    /// `sqlite3_open_v2` (SQLITE_OPEN_CREATE) creates only the file, never
    /// intermediate directories — without this the first launch fails with
    /// SQLITE_CANTOPEN and drops into the in-memory fallback.
    init(directory: URL? = nil) throws {
        let appSupport = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        let dbURL = appSupport.appendingPathComponent("ydoc_snapshots.sqlite")
        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        AppLog.info(.database, "Opening database at \(dbURL.path)")

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(path: dbURL.path, configuration: config)
        try Self.migrate(queue)
        self.dbQueue = queue
    }

    /// In-memory fallback when on-disk DB cannot be opened (corruption, write-protection).
    /// App will function but snapshots won't persist across launches.
    static func makeInMemoryFallback() throws -> YrsDatabase {
        dbInitFailed = true
        return try makeInMemoryQueue()
    }

    /// In-memory DB for XCTest/UI-test hosts. Does not set `dbInitFailed` — the
    /// ephemeral store is expected, not a corruption recovery path.
    static func makeInMemoryForTesting() throws -> YrsDatabase {
        try makeInMemoryQueue()
    }

    private static func makeInMemoryQueue() throws -> YrsDatabase {
        let queue = try DatabaseQueue(configuration: Configuration())
        try migrate(queue)
        return YrsDatabase(dbQueue: queue)
    }

    static func logInitFailure(_ error: Error) {
        AppLog.error(.database, "Failed to open on-disk database, falling back to in-memory: \(error)")
    }

    private init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    private static func migrate(_ dbQueue: DatabaseQueue) throws {
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
            try db.create(
                index: "offline_sync_queue_docKey_createdAt",
                on: "offline_sync_queue",
                columns: ["docKey", "createdAt"]
            )
        }

        migrator.registerMigration("v3_create_reminders_item_map") { db in
            try db.create(table: "reminders_item_map") { t in
                t.column("itemId", .text).primaryKey()
                t.column("reminderId", .text).notNull()
                t.column("listId", .text).notNull()
                t.column("lastLabel", .text).notNull()
                t.column("lastCompleted", .boolean).notNull().defaults(to: false)
                t.column("updatedAt", .text).notNull()
            }
            try db.create(
                index: "reminders_item_map_listId",
                on: "reminders_item_map",
                columns: ["listId"]
            )
        }

        migrator.registerMigration("v4_create_yjs_wire_snapshots") { db in
            try db.create(table: "yjs_wire_snapshots") { t in
                t.column("docKey", .text).primaryKey()
                t.column("state", .blob).notNull()
                t.column("updatedAt", .text).notNull()
            }
        }

        // MIK-128: per-recipe sync flags moved out of UserDefaults.standard.
        // Replaces the old `unsyncedRecipeIds:{userId}` plist key (one array per user) and
        // retires the dead-write `lastServerDocBytes:{recipeId}` plist keys.
        migrator.registerMigration("v5_create_recipe_sync_state") { db in
            try db.create(table: "recipe_sync_state") { t in
                t.column("recipeId", .text).primaryKey()
                t.column("unsynced", .boolean).notNull().defaults(to: false)
            }
        }

        // MIK-128 follow-up: the original table omitted userId, so a flag
        // could leak across account switches. Old rows cannot be attributed
        // safely; discard them and recreate the table with an account-scoped
        // composite key. Offline queue/snapshots remain the durable edit path.
        migrator.registerMigration("v6_scope_recipe_sync_state_by_user") { db in
            try db.drop(table: "recipe_sync_state")
            try db.create(table: "recipe_sync_state") { t in
                t.column("userId", .text).notNull()
                t.column("recipeId", .text).notNull()
                t.column("unsynced", .boolean).notNull().defaults(to: false)
                t.primaryKey(["userId", "recipeId"])
            }
        }

        try migrator.migrate(dbQueue)
    }
}
