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

    let applyFailed: Bool = {
        guard let txn = ydoc_write_transaction(doc, 0, nil) else { return true }
        defer { ytransaction_commit(txn) }
        for update in updates {
            guard update.count <= UInt32.max else {
                AppLog.notice(.document, "yrs_update_oversized", data: [
                    "count": "\(update.count)",
                    "limit": "\(UInt32.max)"
                ])
                continue
            }
            let result = update.withUnsafeBytes { buffer -> UInt8 in
                guard let base = buffer.baseAddress else { return 1 }
                return ytransaction_apply(
                    txn,
                    base.assumingMemoryBound(to: CChar.self),
                    UInt32(buffer.count)
                )
            }
            if result != 0 { return true }
        }
        return false
    }()
    if applyFailed { return updates.last }

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

    /// Recipe editing docs: skip GC so yrs does not emit `Skip` structures that y-prosemirror (yjs 13) cannot read.
    private static func createDocument() throws -> UnsafeMutablePointer<YDoc> {
        var opts = yoptions()
        opts.flags |= UInt8(Y_SKIP_GC)
        guard let d = ydoc_new_with_options(opts) else {
            AppLog.error(.document, "yrs_null_pointer", data: ["context": "ydoc_new_with_options"])
            throw YrsError.nullPointer(context: "ydoc_new_with_options")
        }
        return d
    }

    /// Create a new empty Y.Doc.
    init() throws {
        self.doc = try Self.createDocument()
        installUpdateObserver()
    }

    /// Create a Y.Doc and apply an existing binary state.
    init(state: Data) throws {
        let d = try Self.createDocument()
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
            guard buffer.count <= UInt32.max else {
                AppLog.error(.document, "yrs_apply_oversized", data: [
                    "count": "\(buffer.count)",
                    "limit": "\(UInt32.max)"
                ])
                return 2
            }
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
            let ctx = result == 2
                ? "state too large for UInt32: \(state.count)"
                : "ytransaction_apply returned \(result)"
            AppLog.error(.document, "yrs_apply_failed", data: ["context": ctx])
            throw YrsError.applyFailed(context: ctx)
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

    /// Ensures v3 recipe root types exist before the first write transaction on a new doc.
    func ensureRecipeCreateRoots() {
        _ = ymap(doc, "recipe")
        _ = yxmlfragment(doc, "description")
    }

    /// Ensures the collection doc root `Y.Array`s (`recipes`, `folders`) exist
    /// before the first write transaction. `yarray(doc,)` opens its own internal
    /// write transaction in yrs C FFI, so calling it from inside another active
    /// transaction on the same `YDoc` deadlocks on `event_listener::Listener::wait`.
    /// Same rule as `ensureRootMap`/`ensureRecipeCreateRoots`.
    func ensureCollectionRoots() {
        _ = yarray(doc, RecipeFolderConstants.recipesArrayKey)
        _ = yarray(doc, RecipeFolderConstants.foldersArrayKey)
    }

    /// Borrow the root-level `Y.XmlFragment` for the given key (e.g. "description")
    /// within an active transaction. Returns `nil` if the type does not exist.
    /// Use inside `withReadTransaction` / `withWriteTransaction` blocks; do NOT
    /// call `yxmlfragment(doc,)` while a transaction is open (yrs FFI deadlocks).
    /// `nonisolated` — only uses the caller-provided `txn`, no actor state access.
    nonisolated func xmlFragment(txn: OpaquePointer, name: String) -> YrsXmlFragment? {
        guard let branch = ytype_get(txn, name) else { return nil }
        return YrsXmlFragment(branch: branch)
    }

    /// Borrow the root-level `Y.Map` for the given key (e.g. "recipe") within
    /// an active transaction. Convenience parity with `xmlFragment(txn:name:)`.
    /// `nonisolated` — only uses the caller-provided `txn`, no actor state access.
    nonisolated func recipeMap(txn: OpaquePointer, name: String = "recipe") -> YrsMap? {
        guard let branch = ytype_get(txn, name) else { return nil }
        return YrsMap(branch: branch)
    }

    // ─── Transactions ────────────────────────────────────────────────────

    func withReadTransaction<T>(_ block: (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T) throws -> T {
        guard let txn = ydoc_read_transaction(doc) else {
            AppLog.error(.document, "yrs_transaction_error", data: ["context": "ydoc_read_transaction returned null"])
            throw YrsError.transactionError(context: "ydoc_read_transaction returned null")
        }
        defer { ytransaction_commit(txn) }
        return try block(doc, txn)
    }

    func withWriteTransaction<T>(_ block: (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T) throws -> T {
        guard let txn = ydoc_write_transaction(doc, 0, nil) else {
            AppLog.error(.document, "yrs_transaction_error", data: ["context": "ydoc_write_transaction returned null"])
            throw YrsError.transactionError(context: "ydoc_write_transaction returned null")
        }
        defer { ytransaction_commit(txn) }
        return try block(doc, txn)
    }

    // ─── Sync Operations ────────────────────────────────────────────────

    /// Cheap state-vector fingerprint of the current document state.
    ///
    /// Used as a cache key by read-path optimizations (e.g. the XmlFragment→HTML
    /// cache in `DocumentManager`). Returns `nil` only when the underlying FFI
    /// call fails, which should never happen under a valid read transaction.
    func stateVector() -> Data? {
        var len: UInt32 = 0
        guard let txn = ydoc_read_transaction(doc) else { return nil }
        defer { ytransaction_commit(txn) }
        guard let bytes = ytransaction_state_vector_v1(txn, &len) else { return nil }
        defer { ybinary_destroy(bytes, len) }
        return Data(bytes: bytes, count: Int(len))
    }

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