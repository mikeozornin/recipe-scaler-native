import Foundation
import YrsC

/// Actor wrapping a yrs Y.Doc instance. Provides thread-safe access to CRDT documents.
actor YrsDocument {
    private let doc: UnsafeMutablePointer<YDoc>

    /// Create a new empty Y.Doc.
    init() throws {
        guard let d = ydoc_new() else {
            throw YrsError.nullPointer(context: "ydoc_new")
        }
        self.doc = d
    }

    /// Create a Y.Doc and apply an existing binary state.
    init(state: Data) throws {
        guard let d = ydoc_new() else {
            throw YrsError.nullPointer(context: "ydoc_new")
        }
        self.doc = d

        // Apply the initial state
        let result = state.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> UInt8 in
            guard let baseAddress = buffer.baseAddress else { return 1 }
            guard let txn = ydoc_write_transaction(d, 0, nil) else { return 1 }
            let res = ytransaction_apply(
                txn,
                baseAddress.assumingMemoryBound(to: CChar.self),
                UInt32(buffer.count)
            )
            ytransaction_commit(txn)
            return res
        }
        if result != 0 {
            ydoc_destroy(d)
            throw YrsError.applyFailed(context: "ytransaction_apply returned \(result)")
        }
    }

    deinit {
        ydoc_destroy(doc)
    }

    // ─── Transactions ────────────────────────────────────────────────────

    /// Execute a read-only transaction. Passes raw C pointers (YDoc*, YTransaction*) to the block.
    func withReadTransaction<T>(_ block: (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T) throws -> T {
        guard let txn = ydoc_read_transaction(doc) else {
            throw YrsError.transactionError(context: "ydoc_read_transaction returned null")
        }
        defer { ytransaction_commit(txn) }
        return try block(doc, txn)
    }

    /// Execute a write transaction. NOT used in Phase 2 (read-only), but available for Phase 3.
    func withWriteTransaction<T>(_ block: (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T) throws -> T {
        guard let txn = ydoc_write_transaction(doc, 0, nil) else {
            throw YrsError.transactionError(context: "ydoc_write_transaction returned null")
        }
        defer { ytransaction_commit(txn) }
        return try block(doc, txn)
    }

    // ─── Sync Operations ────────────────────────────────────────────────

    /// Apply a binary update to this document.
    func applyUpdate(_ data: Data) throws {
        let result = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> UInt8 in
            guard let baseAddress = buffer.baseAddress else { return 1 }
            guard let txn = ydoc_write_transaction(doc, 0, nil) else { return 1 }
            let res = ytransaction_apply(
                txn,
                baseAddress.assumingMemoryBound(to: CChar.self),
                UInt32(buffer.count)
            )
            ytransaction_commit(txn)
            return res
        }
        if result != 0 {
            throw YrsError.applyFailed(context: "ytransaction_apply returned \(result)")
        }
    }

    /// Encode the full state as a binary update for persistence.
    func encodeStateAsUpdate() -> Data? {
        var len: UInt32 = 0
        guard let txn = ydoc_read_transaction(doc) else { return nil }
        defer { ytransaction_commit(txn) }

        guard let bytes = ytransaction_state_diff_v1(
            txn,
            nil, 0,
            &len
        ) else { return nil }
        defer { ybinary_destroy(bytes, len) }

        return Data(bytes: bytes, count: Int(len))
    }

    /// Get the unique client ID of this document.
    var clientId: UInt64 {
        return ydoc_id(doc)
    }
}
