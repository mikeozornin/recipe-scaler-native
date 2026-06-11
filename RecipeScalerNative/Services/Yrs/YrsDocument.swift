import Foundation
import YrsC

private final class UpdateObserverBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Data] = []
    private var suppress = false
    lazy var handler: (Data) -> Void = { [weak self] data in
        self?.append(data)
    }

    func setSuppress(_ value: Bool) {
        lock.lock()
        suppress = value
        if value { pending.removeAll() }
        lock.unlock()
    }

    private func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !suppress else { return }
        pending.append(data)
    }

    func pendingByteCount() -> Int {
        lock.lock()
        let total = pending.reduce(0) { $0 + $1.count }
        lock.unlock()
        return total
    }

    func consumePending() -> Data? {
        lock.lock()
        let batch = pending
        pending.removeAll()
        lock.unlock()
        guard !batch.isEmpty else { return nil }
        if batch.count == 1 { return batch[0] }
        return mergeYjsUpdates(batch)
    }
}

private func mergeYjsUpdates(_ updates: [Data]) -> Data? {
    guard let doc = ydoc_new() else { return updates.last }
    defer { ydoc_destroy(doc) }
    for update in updates {
        let result = update.withUnsafeBytes { buffer -> UInt8 in
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
        if result != 0 { return updates.last }
    }
    guard let txn = ydoc_read_transaction(doc) else { return updates.last }
    defer { ytransaction_commit(txn) }
    var len: UInt32 = 0
    guard let bytes = ytransaction_state_diff_v1(txn, nil, 0, &len) else { return updates.last }
    defer { ybinary_destroy(bytes, len) }
    return Data(bytes: bytes, count: Int(len))
}

/// Actor wrapping a yrs Y.Doc instance. Provides thread-safe access to CRDT documents.
actor YrsDocument {
    private let doc: UnsafeMutablePointer<YDoc>
    private var updateSubscription: UnsafeMutablePointer<YSubscription>?
    private var updateObserverBox: UnsafeMutableRawPointer?
    private var updateObserverBoxRef: UpdateObserverBox?

    func setOnLocalUpdateHandler(_ handler: @escaping @Sendable (Data) -> Void) {
        _ = handler
    }

    /// Create a new empty Y.Doc.
    init() throws {
        guard let d = ydoc_new() else {
            throw YrsError.nullPointer(context: "ydoc_new")
        }
        self.doc = d
        installUpdateObserver()
    }

    /// Create a Y.Doc and apply an existing binary state.
    init(state: Data) throws {
        guard let d = ydoc_new() else {
            throw YrsError.nullPointer(context: "ydoc_new")
        }
        self.doc = d
        try Self.applyState(state, to: d)
        installUpdateObserver()
    }

    deinit {
        if let updateSubscription {
            yunobserve(updateSubscription)
        }
        if let updateObserverBox {
            Unmanaged<UpdateObserverBox>.fromOpaque(updateObserverBox).release()
        }
        updateObserverBoxRef = nil
        ydoc_destroy(doc)
    }

    private static func applyState(_ state: Data, to doc: UnsafeMutablePointer<YDoc>) throws {
        let result = state.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> UInt8 in
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

    private func installUpdateObserver() {
        let box = UpdateObserverBox()
        updateObserverBoxRef = box
        let state = Unmanaged.passRetained(box).toOpaque()
        updateObserverBox = state

        updateSubscription = ydoc_observe_updates_v1(doc, state) { state, len, bytes in
            guard let state, let bytes else { return }
            let box = Unmanaged<UpdateObserverBox>.fromOpaque(state).takeUnretainedValue()
            let data = Data(bytes: bytes, count: Int(len))
            box.handler(data)
        }
    }

    func consumePendingLocalUpdates() -> Data? {
        updateObserverBoxRef?.consumePending()
    }

    func pendingLocalUpdateByteCount() -> Int {
        updateObserverBoxRef?.pendingByteCount() ?? 0
    }

    /// Ensures a root-level shared type exists. Call only when no Y transaction is open (`ymap(doc,)` deadlocks with active txn).
    func ensureRootMap(named name: String) {
        _ = ymap(doc, name)
    }

    // ─── Transactions ────────────────────────────────────────────────────

    func withReadTransaction<T>(_ block: (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T) throws -> T {
        guard let txn = ydoc_read_transaction(doc) else {
            throw YrsError.transactionError(context: "ydoc_read_transaction returned null")
        }
        defer { ytransaction_commit(txn) }
        return try block(doc, txn)
    }

    func withWriteTransaction<T>(_ block: (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T) throws -> T {
        guard let txn = ydoc_write_transaction(doc, 0, nil) else {
            throw YrsError.transactionError(context: "ydoc_write_transaction returned null")
        }
        defer { ytransaction_commit(txn) }
        return try block(doc, txn)
    }

    // ─── Sync Operations ────────────────────────────────────────────────

    func applyUpdate(_ data: Data) throws {
        updateObserverBoxRef?.setSuppress(true)
        defer {
            _ = updateObserverBoxRef?.consumePending()
            updateObserverBoxRef?.setSuppress(false)
        }
        try Self.applyState(data, to: doc)
    }

    /// Apply a local edit and let `ydoc_observe_updates_v1` capture outbound sync bytes (yjs v1).
    func applyLocalUpdate(_ data: Data) throws {
        try Self.applyState(data, to: doc)
    }

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

    var clientId: UInt64 {
        return ydoc_id(doc)
    }
}