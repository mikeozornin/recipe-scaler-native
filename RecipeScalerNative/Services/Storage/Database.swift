import Foundation
import GRDB
import OSLog

/// GRDB database setup and migration for Y.Doc snapshot storage.
///
/// Database file: `ApplicationSupport/ydoc_snapshots.sqlite`
/// Schema: single `ydoc_snapshots` table with WAL mode for concurrent reads.
final class YrsDatabase {
    let dbQueue: DatabaseQueue
    private static let logger = Logger(subsystem: "com.recipescaler.native", category: "YrsDatabase")

    init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        let dbURL = appSupport.appendingPathComponent("ydoc_snapshots.sqlite")
        YrsDatabase.logger.info("Opening database at \(dbURL.path)")

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        self.dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        try migrate()
    }

    private func migrate() throws {
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

        try migrator.migrate(dbQueue)
    }
}
