import Foundation
import YrsC

/// Debounces outgoing Y.Doc updates (~1s idle), matching web `yjs-client.ts` FLUSH_MS.
actor UpdateDebouncer {
    private let flushIntervalNs: UInt64 = 1_000_000_000
    private var pendingByRecipeId: [String: Data] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private let onFlush: @Sendable (String, Data) async -> Void

    init(onFlush: @escaping @Sendable (String, Data) async -> Void) {
        self.onFlush = onFlush
    }

    func schedule(recipeId: String, update: Data) {
        if let existing = pendingByRecipeId[recipeId] {
            pendingByRecipeId[recipeId] = mergeUpdates(existing, update) ?? update
        } else {
            pendingByRecipeId[recipeId] = update
        }

        tasks[recipeId]?.cancel()
        tasks[recipeId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.flushIntervalNs ?? 1_000_000_000)
            await self?.flush(recipeId: recipeId)
        }
    }

    func flushNow(recipeId: String) async {
        tasks[recipeId]?.cancel()
        tasks[recipeId] = nil
        await flush(recipeId: recipeId)
    }

    private func flush(recipeId: String) async {
        guard let payload = pendingByRecipeId.removeValue(forKey: recipeId) else { return }
        tasks[recipeId] = nil
        await onFlush(recipeId, payload)
    }

    /// Apply `second` on top of `first` in a throwaway doc; fallback to `second` if merge fails.
    private func mergeUpdates(_ first: Data, _ second: Data) -> Data? {
        guard let doc = ydoc_new() else { return nil }
        defer { ydoc_destroy(doc) }

        guard (try? apply(first, to: doc)) != nil,
              (try? apply(second, to: doc)) != nil,
              let txn = ydoc_read_transaction(doc) else {
            return nil
        }
        defer { ytransaction_commit(txn) }
        var len: UInt32 = 0
        guard let bytes = ytransaction_state_diff_v1(txn, nil, 0, &len) else { return nil }
        defer { ybinary_destroy(bytes, len) }
        return Data(bytes: bytes, count: Int(len))
    }

    private func apply(_ data: Data, to doc: UnsafeMutablePointer<YDoc>) throws {
        let result = data.withUnsafeBytes { buffer -> UInt8 in
            guard let base = buffer.baseAddress else { return 1 }
            guard let txn = ydoc_write_transaction(doc, 0, nil) else { return 1 }
            let res = ytransaction_apply(
                txn,
                base.assumingMemoryBound(to: CChar.self),
                UInt32(buffer.count)
            )
            ytransaction_commit(txn)
            return res
        }
        if result != 0 {
            throw YrsError.applyFailed(context: "merge apply failed")
        }
    }
}