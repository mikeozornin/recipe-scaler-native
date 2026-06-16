//
//  RemindersSyncService.swift
//  RecipeScalerNative
//
//  Bidirectional mirror between the CRDT shopping list and Apple Reminders.
//
//  Architecture:
//    • CRDT is the single source of truth; Reminders is a synchronized copy on iOS.
//    • Web, MCP tools, and public share links are unaffected.
//    • Correlation key: `[rs:<itemId>]` token embedded in `EKReminder.notes`.
//      This survives iCloud sync, preventing duplicate reminders on multiple devices.
//    • Local `RemindersMapStore` is a speed-cache only; the notes token is authoritative.
//
//  Sync rules:
//    CRDT → Reminders (on snapshot change):
//      • New item  → create reminder, cache mapping.
//      • Changed   → update title / completion if dirty.
//      • Removed (uncompleted) → delete reminder.
//      • Removed (completed)   → leave as-is; acts as purchase history in Reminders.
//    Reminders → CRDT (on EKEventStoreChanged / foreground):
//      • Completion flipped → last-write-wins (completionDate vs purchasedAt).
//      • Reminder deleted manually → restore on next CRDT pass (CRDT wins).
//      • Reminder added manually (no token) → imported into CRDT as a manual item (no recipe).

import Foundation
import Combine
import EventKit

import UIKit

@MainActor
final class RemindersSyncService: ObservableObject {

    // MARK: - Published state (read by AccountSettingsViewModel)

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var availableLists: [EKCalendar] = []

    // MARK: - Private

    private let store = EKEventStore()
    private let mapStore: RemindersMapStore
    private weak var syncService: YjsSyncService?
    private var cancellables = Set<AnyCancellable>()
    private var isRunningSync = false

    static let dedicatedListName = "Recipe Scaler"

    // MARK: - Init

    init(mapStore: RemindersMapStore) {
        self.mapStore = mapStore
        refreshAuthorizationStatus()
    }

    // MARK: - Wiring

    /// Call after both services are initialized. Starts observing the shopping snapshot.
    func attach(to syncService: YjsSyncService) {
        self.syncService = syncService
        guard RemindersSyncPreferences.isEnabled else { return }

        startObserving(syncService: syncService)
    }

    // MARK: - Authorization

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            refreshAuthorizationStatus()
            return granted
        } catch {
            AppLog.error(.reminders, "Reminders access request failed: \(error)")
            return false
        }
    }

    // MARK: - Enabling / disabling

    func enable(syncService: YjsSyncService) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .denied || status == .restricted {
            return false
        }

        var granted = status == .fullAccess
        if status == .notDetermined {
            granted = await requestAccess()
        }
        guard granted else { return false }

        RemindersSyncPreferences.isEnabled = true
        startObserving(syncService: syncService)
        await reconcileCRDTToReminders(snapshot: syncService.shoppingSnapshot)
        return true
    }

    func disable() {
        RemindersSyncPreferences.isEnabled = false
        stopObserving()
    }

    // MARK: - List management

    func loadAvailableLists() {
        availableLists = store.calendars(for: .reminder).sorted { $0.title < $1.title }
    }

    func selectList(_ identifier: String, syncService: YjsSyncService) async {
        guard identifier != RemindersSyncPreferences.listIdentifier else { return }
        RemindersSyncPreferences.listIdentifier = identifier
        // Clear the cache; old reminder IDs are stale for the new list.
        try? await mapStore.deleteAll()
        // Push the current snapshot into the new list.
        await reconcileCRDTToReminders(snapshot: syncService.shoppingSnapshot)
    }

    // MARK: - Observation

    private func startObserving(syncService: YjsSyncService) {
        stopObserving()

        // CRDT → Reminders: react to every snapshot change.
        syncService.$shoppingSnapshot
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                Task { await self.reconcileCRDTToReminders(snapshot: snapshot) }
            }
            .store(in: &cancellables)

        // Reminders → CRDT: react to external EventKit changes.
        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reconcileRemindersToUserSnapshot() }
            }
            .store(in: &cancellables)
    }

    private func stopObserving() {
        cancellables.removeAll()
    }

    // MARK: - CRDT → Reminders reconciliation

    func reconcileCRDTToReminders(snapshot: ShoppingListSnapshot) async {
        guard RemindersSyncPreferences.isEnabled,
              EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        guard !isRunningSync else { return }
        isRunningSync = true
        defer { isRunningSync = false }

        let calendar = resolveOrCreateCalendar()

        let crdtIds = Set(snapshot.items.map(\.id))

        // 1. Upsert: create or update reminders for every current CRDT item.
        for item in snapshot.items {
            await upsertReminder(for: item, in: calendar)
        }

        // 2. Clean up items no longer in CRDT.
        // Completed reminders are left as-is (they serve as a purchase history in Reminders).
        // Only uncompleted orphans are deleted.
        guard let entries = try? await mapStore.allEntries() else { return }
        for entry in entries where !crdtIds.contains(entry.itemId) {
            let reminder = store.calendarItem(withIdentifier: entry.reminderId) as? EKReminder
            if reminder?.isCompleted != true {
                deleteReminder(withId: entry.reminderId)
            }
            try? await mapStore.delete(itemId: entry.itemId)
        }
    }

    private func upsertReminder(for item: ShoppingListItem, in calendar: EKCalendar) async {
        // Try to find an existing reminder via the local cache or by scanning notes.
        var reminder: EKReminder?
        if let entry = try? await mapStore.entry(forItemId: item.id) {
            reminder = store.calendarItem(withIdentifier: entry.reminderId) as? EKReminder
        }
        if reminder == nil {
            reminder = await findReminderByToken(itemId: item.id, in: calendar)
        }

        if let existing = reminder {
            // Update only if something changed.
            let labelChanged = existing.title != item.label
            let completedChanged = existing.isCompleted != item.purchased
            guard labelChanged || completedChanged else { return }

            if labelChanged { existing.title = item.label }
            if completedChanged {
                existing.isCompleted = item.purchased
                existing.completionDate = item.purchased
                    ? (item.purchasedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date())
                    : nil
            }
            try? store.save(existing, commit: true)
            try? await mapStore.upsert(
                itemId: item.id,
                reminderId: existing.calendarItemIdentifier,
                listId: calendar.calendarIdentifier,
                lastLabel: item.label,
                lastCompleted: item.purchased
            )
        } else {
            // Create a new reminder.
            let newReminder = EKReminder(eventStore: store)
            newReminder.calendar = calendar
            newReminder.title = item.label
            newReminder.notes = buildNotes(item: item)
            newReminder.isCompleted = item.purchased
            if item.purchased, let ms = item.purchasedAt {
                newReminder.completionDate = Date(timeIntervalSince1970: Double(ms) / 1000)
            }
            do {
                try store.save(newReminder, commit: true)
                try? await mapStore.upsert(
                    itemId: item.id,
                    reminderId: newReminder.calendarItemIdentifier,
                    listId: calendar.calendarIdentifier,
                    lastLabel: item.label,
                    lastCompleted: item.purchased
                )
            } catch {
                AppLog.error(.reminders, "Failed to save reminder for item \(item.id): \(error)")
            }
        }
    }

    private func deleteReminder(withId reminderId: String) {
        guard let reminder = store.calendarItem(withIdentifier: reminderId) as? EKReminder else { return }
        try? store.remove(reminder, commit: true)
    }

    // MARK: - Reminders → CRDT reconciliation

    func reconcileRemindersToUserSnapshot() async {
        guard RemindersSyncPreferences.isEnabled,
              EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let syncService else { return }

        let snapshot = syncService.shoppingSnapshot
        let calendar = resolveOrCreateCalendar()

        let predicate = store.predicateForReminders(in: [calendar])
        let reminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }

        for reminder in reminders {
            guard let itemId = extractToken(from: reminder.notes) else { continue }
            guard let item = snapshot.items.first(where: { $0.id == itemId }) else { continue }

            let reminderCompleted = reminder.isCompleted
            guard reminderCompleted != item.purchased else { continue }

            // Last-write-wins: compare timestamps.
            let reminderMs = reminder.completionDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
            let crdtMs = item.purchasedAt ?? 0
            let reminderWins = reminderCompleted
                ? reminderMs > crdtMs
                : (reminderMs == 0 && crdtMs == 0) || reminderMs < crdtMs

            if reminderWins {
                try? await syncService.setShoppingItemPurchased(id: itemId, purchased: reminderCompleted)
                AppLog.info(.reminders, "Reminders→CRDT: item \(itemId) purchased=\(reminderCompleted)")
            }
        }

        // Import reminders that were added manually (no [rs:id] token) into the CRDT shopping list.
        for reminder in reminders where extractToken(from: reminder.notes) == nil {
            let reminderId = reminder.calendarItemIdentifier
            // Deduplication by EKIdentifier — guards against a failed token write-back on a
            // previous pass or a rapid EKEventStoreChanged / foreground re-entry.
            if (try? await mapStore.entry(forReminderId: reminderId)) != nil { continue }

            let label = reminder.title ?? ""
            guard !label.isEmpty else { continue }

            let itemId = UUID().uuidString
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let item = ShoppingListItem(
                id: itemId,
                label: label,
                purchased: reminder.isCompleted,
                purchasedAt: reminder.completionDate.map { Int64($0.timeIntervalSince1970 * 1000) },
                createdAt: now
            )

            // Pre-cache the mapping BEFORE touching the CRDT snapshot. This ensures the
            // CRDT→Reminders reconciliation triggered by the snapshot change finds the
            // existing reminder in the cache instead of creating a duplicate.
            try? await mapStore.upsert(
                itemId: itemId,
                reminderId: reminderId,
                listId: calendar.calendarIdentifier,
                lastLabel: label,
                lastCompleted: item.purchased
            )

            do {
                try await syncService.addShoppingItem(item)
                // Stamp the correlation token so other devices and future passes
                // recognise this reminder as a tracked item.
                let base = reminder.notes ?? ""
                reminder.notes = base.isEmpty
                    ? "\(Self.tokenPrefix)\(itemId)\(Self.tokenSuffix)"
                    : "\(base)\n\(Self.tokenPrefix)\(itemId)\(Self.tokenSuffix)"
                try? store.save(reminder, commit: true)
                AppLog.info(.reminders, "Reminders→CRDT: imported '\(label)' as item \(itemId)")
            } catch {
                // Roll back the pre-cached entry so the next pass retries cleanly.
                try? await mapStore.delete(itemId: itemId)
                AppLog.error(.reminders, "Reminders→CRDT: import failed for '\(label)': \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// Returns (or creates) the calendar to sync into.
    private func resolveOrCreateCalendar() -> EKCalendar {
        let prefs = RemindersSyncPreferences.self

        // User chose a specific existing list.
        if !prefs.usesDedicatedList,
           let cal = store.calendar(withIdentifier: prefs.listIdentifier) {
            return cal
        }

        // Check if the dedicated list already exists.
        if let existing = store.calendars(for: .reminder)
            .first(where: { $0.title == Self.dedicatedListName }) {
            return existing
        }

        // Create the dedicated list.
        let newCal = EKCalendar(for: .reminder, eventStore: store)
        newCal.title = Self.dedicatedListName
        newCal.cgColor = UIColor(red: 1.0, green: 0.325, blue: 0.094, alpha: 1.0).cgColor // #FF5318
        newCal.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        do {
            try store.saveCalendar(newCal, commit: true)
            AppLog.info(.reminders, "Created dedicated Reminders list '\(Self.dedicatedListName)'")
        } catch {
            AppLog.error(.reminders, "Failed to create Reminders list: \(error)")
        }
        return newCal
    }

    /// Scans all reminders in `calendar` for the `[rs:<itemId>]` token and returns the match.
    private func findReminderByToken(itemId: String, in calendar: EKCalendar) async -> EKReminder? {
        let predicate = store.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let found = reminders?.first { self.extractToken(from: $0.notes) == itemId }
                continuation.resume(returning: found)
            }
        }
    }

    // MARK: - Notes token encoding

    private static let tokenPrefix = "[rs:"
    private static let tokenSuffix = "]"

    private func buildNotes(item: ShoppingListItem) -> String {
        var parts: [String] = []
        if !item.recipeName.isEmpty {
            let fromLabel = Bundle.currentLocalizedString("account.reminders.note.from")
            parts.append("\(fromLabel): \(item.recipeName)")
        }
        parts.append("\(Self.tokenPrefix)\(item.id)\(Self.tokenSuffix)")
        return parts.joined(separator: "\n")
    }

    private func extractToken(from notes: String?) -> String? {
        guard let notes,
              let prefixRange = notes.range(of: Self.tokenPrefix),
              let suffixRange = notes.range(of: Self.tokenSuffix, range: prefixRange.upperBound..<notes.endIndex)
        else { return nil }
        return String(notes[prefixRange.upperBound..<suffixRange.lowerBound])
    }
}
