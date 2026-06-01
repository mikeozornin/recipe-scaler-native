import Foundation
import GRDB

/// A Y.Doc snapshot record stored in SQLite.
struct YDocSnapshot: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "ydoc_snapshots"

    /// Document key: `{userId}:collection` or `{userId}:recipe:{recipeId}`
    var docKey: String
    /// Binary Y.Doc state (encodeStateAsUpdate output)
    var state: Data
    /// Server-provided timestamp of last successful sync
    var lastSyncedAt: String?
    /// Local timestamp of when this snapshot was last written
    var updatedAt: String
}

/// Thread-safe CRUD operations for Y.Doc snapshots using GRDB.
actor YDocStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Load a snapshot by document key. Returns nil if not found.
    func loadSnapshot(docKey: String) throws -> YDocSnapshot? {
        try dbQueue.read { db in
            try YDocSnapshot.fetchOne(db, key: docKey)
        }
    }

    /// Save or update a snapshot. Upserts based on docKey.
    func saveSnapshot(docKey: String, state: Data, lastSyncedAt: String?) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        var snapshot = YDocSnapshot(
            docKey: docKey,
            state: state,
            lastSyncedAt: lastSyncedAt,
            updatedAt: now
        )
        try dbQueue.write { db in
            try snapshot.save(db)
        }
    }

    /// Delete a snapshot by document key.
    func deleteSnapshot(docKey: String) throws {
        try dbQueue.write { db in
            _ = try YDocSnapshot.deleteOne(db, key: docKey)
        }
    }

    /// Get all stored document keys. Useful for identifying what's cached locally.
    func allSnapshotKeys() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT docKey FROM ydoc_snapshots")
        }
    }

    /// Delete all snapshots. Used when switching user accounts.
    func deleteAll() throws {
        try dbQueue.write { db in
            try YDocSnapshot.deleteAll(db)
        }
    }
}
