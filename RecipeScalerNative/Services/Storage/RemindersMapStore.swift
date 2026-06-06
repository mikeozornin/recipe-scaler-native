//
//  RemindersMapStore.swift
//  RecipeScalerNative
//

import Foundation
import GRDB

/// A cached mapping between a `ShoppingListItem.id` and its corresponding
/// `EKReminder.calendarItemIdentifier`. Stored in the same SQLite database as Y.Doc snapshots.
///
/// This is a performance cache only – the authoritative correlation key is the
/// `[rs:<itemId>]` token embedded in `EKReminder.notes`, which survives iCloud sync.
struct RemindersMapEntry: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "reminders_item_map"

    /// `ShoppingListItem.id` (UUID string) — primary key.
    var itemId: String
    /// `EKReminder.calendarItemIdentifier` of the mirrored reminder.
    var reminderId: String
    /// `EKCalendar.calendarIdentifier` of the list this reminder lives in.
    var listId: String
    /// Last-known `label` value; used for cheap dirty-check before updating the reminder.
    var lastLabel: String
    /// Last-known `purchased` value; used for cheap dirty-check.
    var lastCompleted: Bool
    /// ISO-8601 timestamp of the last time this entry was written.
    var updatedAt: String
}

/// Thread-safe CRUD operations for the Reminders ↔ shopping item mapping.
actor RemindersMapStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Reading

    func entry(forItemId itemId: String) throws -> RemindersMapEntry? {
        try dbQueue.read { db in
            try RemindersMapEntry.fetchOne(db, key: itemId)
        }
    }

    func allEntries() throws -> [RemindersMapEntry] {
        try dbQueue.read { db in
            try RemindersMapEntry.fetchAll(db)
        }
    }

    func entriesForList(_ listId: String) throws -> [RemindersMapEntry] {
        try dbQueue.read { db in
            try RemindersMapEntry
                .filter(Column("listId") == listId)
                .fetchAll(db)
        }
    }

    func entry(forReminderId reminderId: String) throws -> RemindersMapEntry? {
        try dbQueue.read { db in
            try RemindersMapEntry
                .filter(Column("reminderId") == reminderId)
                .fetchOne(db)
        }
    }

    // MARK: - Writing

    func upsert(itemId: String, reminderId: String, listId: String,
                lastLabel: String, lastCompleted: Bool) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        var entry = RemindersMapEntry(
            itemId: itemId,
            reminderId: reminderId,
            listId: listId,
            lastLabel: lastLabel,
            lastCompleted: lastCompleted,
            updatedAt: now
        )
        try dbQueue.write { db in
            try entry.save(db)
        }
    }

    func delete(itemId: String) throws {
        try dbQueue.write { db in
            _ = try RemindersMapEntry.deleteOne(db, key: itemId)
        }
    }

    /// Remove all entries. Used when the user switches the target Reminders list or disables sync.
    func deleteAll() throws {
        try dbQueue.write { db in
            try RemindersMapEntry.deleteAll(db)
        }
    }
}
