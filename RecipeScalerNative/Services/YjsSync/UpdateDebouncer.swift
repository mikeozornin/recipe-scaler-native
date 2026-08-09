import Foundation

struct UpdateDebouncerBatch: Sendable {
    let userId: String
    /// Account session identity. It remains stable across a same-account
    /// socket reconnect, but rotates on logout/account switch.
    let sessionId: UUID
    let updates: [Data]
}

private struct UpdateDebouncerKey: Hashable, Sendable {
    let userId: String
    let sessionId: UUID
    let recipeId: String
}

/// Debounces outgoing Y.Doc updates (~1s idle), matching web `yjs-client.ts` FLUSH_MS.
/// Pending updates are queued and flushed sequentially — web uses `Y.mergeUpdates`, but
/// yrs has no equivalent; applying incremental updates to an empty throwaway doc and taking
/// `state_diff_v1` produces no-op `00 00` payloads.
actor UpdateDebouncer {
    private let flushIntervalNs: UInt64 = 1_000_000_000
    private var pendingByKey: [UpdateDebouncerKey: [Data]] = [:]
    private var tasks: [UpdateDebouncerKey: Task<Void, Never>] = [:]
    private let onFlush: @Sendable (String, UUID, String, Data) async -> Void

    init(onFlush: @escaping @Sendable (String, UUID, String, Data) async -> Void) {
        self.onFlush = onFlush
    }

    func schedule(userId: String, sessionId: UUID, recipeId: String, update: Data) {
        guard !update.isEmpty else { return }
        let key = UpdateDebouncerKey(userId: userId, sessionId: sessionId, recipeId: recipeId)
        var batch = pendingByKey[key] ?? []
        batch.append(update)
        pendingByKey[key] = batch

        tasks[key]?.cancel()
        tasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.flushIntervalNs ?? 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.flush(key: key)
        }
    }

    /// Drain pending bytes without calling `onFlush` (avoids MainActor ↔ actor deadlock when caller flushes on MainActor).
    func drainPending(userId: String, sessionId: UUID, recipeId: String) -> Data? {
        let batch = drainPendingBatch(userId: userId, sessionId: sessionId, recipeId: recipeId)
        guard let batch, !batch.updates.isEmpty else { return nil }
        return batch.updates.count == 1 ? batch.updates[0] : nil
    }

    func drainPendingBatch(
        userId: String,
        sessionId: UUID,
        recipeId: String
    ) -> UpdateDebouncerBatch? {
        let key = UpdateDebouncerKey(userId: userId, sessionId: sessionId, recipeId: recipeId)
        tasks[key]?.cancel()
        tasks[key] = nil
        guard let batch = pendingByKey.removeValue(forKey: key), !batch.isEmpty else {
            return nil
        }
        return UpdateDebouncerBatch(userId: userId, sessionId: sessionId, updates: batch)
    }

    func flushNow(userId: String, sessionId: UUID, recipeId: String) async {
        await flush(key: UpdateDebouncerKey(userId: userId, sessionId: sessionId, recipeId: recipeId))
    }

    func hasPending(userId: String, sessionId: UUID, recipeId: String) -> Bool {
        let key = UpdateDebouncerKey(userId: userId, sessionId: sessionId, recipeId: recipeId)
        guard let batch = pendingByKey[key] else {
            return false
        }
        return !batch.isEmpty
    }

    /// Drop only one account's delayed work. Same-account reconnects intentionally
    /// keep their pending batches so the replacement socket can flush them.
    func cancel(userId: String) {
        let keys = tasks.keys.filter { $0.userId == userId }
        for key in keys {
            tasks[key]?.cancel()
            tasks.removeValue(forKey: key)
            pendingByKey.removeValue(forKey: key)
        }
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        pendingByKey.removeAll()
    }

    private func flush(key: UpdateDebouncerKey) async {
        guard let batch = drainPendingBatch(
            userId: key.userId,
            sessionId: key.sessionId,
            recipeId: key.recipeId
        ) else {
            return
        }
        let payloads = batch.updates.filter { $0.count > 2 }
        guard !payloads.isEmpty else { return }
        if payloads.count == 1 {
            await onFlush(batch.userId, batch.sessionId, key.recipeId, payloads[0])
            return
        }
        if let merged = try? await YjsMergeHelper.shared.mergeUpdates(payloads) {
            await onFlush(batch.userId, batch.sessionId, key.recipeId, merged)
            return
        }
        for payload in payloads {
            await onFlush(batch.userId, batch.sessionId, key.recipeId, payload)
        }
    }

    private static func hexPrefix(_ data: Data, limit: Int = 8) -> String {
        data.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
