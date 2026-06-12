import Foundation

/// Debounces outgoing Y.Doc updates (~1s idle), matching web `yjs-client.ts` FLUSH_MS.
/// Pending updates are queued and flushed sequentially — web uses `Y.mergeUpdates`, but
/// yrs has no equivalent; applying incremental updates to an empty throwaway doc and taking
/// `state_diff_v1` produces no-op `00 00` payloads.
actor UpdateDebouncer {
    private let flushIntervalNs: UInt64 = 1_000_000_000
    private var pendingByRecipeId: [String: [Data]] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private let onFlush: @Sendable (String, Data) async -> Void

    init(onFlush: @escaping @Sendable (String, Data) async -> Void) {
        self.onFlush = onFlush
    }

    func schedule(recipeId: String, update: Data) {
        guard !update.isEmpty else { return }
        var batch = pendingByRecipeId[recipeId] ?? []
        batch.append(update)
        pendingByRecipeId[recipeId] = batch

        tasks[recipeId]?.cancel()
        tasks[recipeId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.flushIntervalNs ?? 1_000_000_000)
            await self?.flush(recipeId: recipeId)
        }
    }

    /// Drain pending bytes without calling `onFlush` (avoids MainActor ↔ actor deadlock when caller flushes on MainActor).
    func drainPending(recipeId: String) -> Data? {
        let batch = drainPendingBatch(recipeId: recipeId)
        guard let batch, !batch.isEmpty else { return nil }
        return batch.count == 1 ? batch[0] : nil
    }

    func drainPendingBatch(recipeId: String) -> [Data]? {
        tasks[recipeId]?.cancel()
        tasks[recipeId] = nil
        let batch = pendingByRecipeId.removeValue(forKey: recipeId)
        guard let batch, !batch.isEmpty else { return nil }
        return batch
    }

    func flushNow(recipeId: String) async {
        await flush(recipeId: recipeId)
    }

    private func flush(recipeId: String) async {
        guard let batch = drainPendingBatch(recipeId: recipeId) else { return }
        for (index, payload) in batch.enumerated() {
            guard payload.count > 2 else {
                continue
            }
            await onFlush(recipeId, payload)
        }
    }

    private static func hexPrefix(_ data: Data, limit: Int = 8) -> String {
        data.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
