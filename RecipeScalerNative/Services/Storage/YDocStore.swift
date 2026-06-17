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

    /// Load snapshots for multiple doc keys in a single database read.
    func loadSnapshots(docKeys: [String]) throws -> [String: YDocSnapshot] {
        guard !docKeys.isEmpty else { return [:] }
        return try dbQueue.read { db in
            let rows = try YDocSnapshot.fetchAll(db, keys: docKeys)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.docKey, $0) })
        }
    }

    /// Return only the doc keys that have a snapshot row.
    func existingSnapshotKeys(docKeys: [String]) throws -> Set<String> {
        guard !docKeys.isEmpty else { return [] }
        return try dbQueue.read { db in
            let keys = try String.fetchAll(
                db,
                sql: """
                SELECT docKey FROM ydoc_snapshots
                WHERE docKey IN (\(docKeys.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: StatementArguments(docKeys)
            )
            return Set(keys)
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

    // MARK: - Offline write queue (Phase 3)

    func enqueueOfflineUpdate(docKey: String, recipeId: String, yjsUpdate: Data) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        var entry = OfflineSyncEntry(
            id: nil,
            docKey: docKey,
            recipeId: recipeId,
            yjsUpdate: yjsUpdate,
            createdAt: now,
            attemptCount: 0
        )
        try dbQueue.write { db in
            try entry.insert(db)
        }
    }

    func fetchOfflineQueue() throws -> [OfflineSyncEntry] {
        try dbQueue.read { db in
            try OfflineSyncEntry
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func deleteOfflineEntry(id: Int64) throws {
        try dbQueue.write { db in
            _ = try OfflineSyncEntry.deleteOne(db, key: id)
        }
    }

    func deleteOfflineQueue(forDocKey docKey: String) throws {
        try dbQueue.write { db in
            try OfflineSyncEntry
                .filter(Column("docKey") == docKey)
                .deleteAll(db)
        }
    }

    func deleteAllOfflineQueue() throws {
        try dbQueue.write { db in
            try OfflineSyncEntry.deleteAll(db)
        }
    }

    func deleteOfflineQueue(forRecipeId recipeId: String) throws {
        try dbQueue.write { db in
            try OfflineSyncEntry
                .filter(Column("recipeId") == recipeId)
                .deleteAll(db)
        }
    }

    /// Distinct recipe ids present in the offline queue (single read).
    func fetchOfflineQueueRecipeIds() throws -> Set<String> {
        try dbQueue.read { db in
            let ids = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT recipeId FROM offline_sync_queue"
            )
            return Set(ids)
        }
    }

    /// Delete multiple queue rows in one write transaction.
    func deleteOfflineEntries(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids {
                _ = try OfflineSyncEntry.deleteOne(db, key: id)
            }
        }
    }

    // MARK: - Yjs wire snapshots (description offline sync)

    func saveYjsWireSnapshot(docKey: String, state: Data) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        var snapshot = YjsWireSnapshot(docKey: docKey, state: state, updatedAt: now)
        try dbQueue.write { db in
            try snapshot.save(db)
        }
    }

    func loadYjsWireSnapshot(docKey: String) throws -> YjsWireSnapshot? {
        try dbQueue.read { db in
            try YjsWireSnapshot.fetchOne(db, key: docKey)
        }
    }

    func loadYjsWireSnapshots(docKeys: [String]) throws -> [String: YjsWireSnapshot] {
        guard !docKeys.isEmpty else { return [:] }
        return try dbQueue.read { db in
            let rows = try YjsWireSnapshot.fetchAll(db, keys: docKeys)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.docKey, $0) })
        }
    }

    func deleteYjsWireSnapshot(docKey: String) throws {
        try dbQueue.write { db in
            _ = try YjsWireSnapshot.deleteOne(db, key: docKey)
        }
    }

    func deleteAllYjsWireSnapshots() throws {
        try dbQueue.write { db in
            try YjsWireSnapshot.deleteAll(db)
        }
    }

    func allYjsWireSnapshotKeys() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT docKey FROM yjs_wire_snapshots")
        }
    }
}

extension YDocStore {
    /// In-memory store with migrated schema — for unit tests only.
    static func inMemory() throws -> YDocStore {
        let database = try YrsDatabase.makeInMemoryFallback()
        return YDocStore(dbQueue: database.dbQueue)
    }
}
