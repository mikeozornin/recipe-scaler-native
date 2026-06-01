import Foundation
import YrsC

/// Read operations on a Y.Map shared type within a Y.Doc.
struct YrsMap {
    let branch: UnsafeMutablePointer<Branch>

    // ─── Primitive Reads ─────────────────────────────────────────────────

    func string(key: String, txn: OpaquePointer) -> String? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        guard let cStr = youtput_read_string(output) else { return nil }
        defer { ystring_destroy(cStr) }
        return String(cString: cStr)
    }

    func bool(key: String, txn: OpaquePointer) -> Bool? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        guard let ptr = youtput_read_bool(output) else { return nil }
        return ptr.pointee != 0
    }

    func double(key: String, txn: OpaquePointer) -> Double? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        guard let ptr = youtput_read_float(output) else { return nil }
        return ptr.pointee
    }

    func int(key: String, txn: OpaquePointer) -> Int? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        guard let ptr = youtput_read_long(output) else { return nil }
        return Int(ptr.pointee)
    }

    /// Get the raw YrsValue for a key. Caller is responsible for lifecycle.
    func value(key: String, txn: OpaquePointer) -> YrsValue {
        guard let output = ymap_get(branch, txn, key) else {
            fatalError("ymap_get returned null for key '\(key)'")
        }
        return YrsValue(output)
    }

    // ─── Nested Type Reads ───────────────────────────────────────────────

    func nestedMap(key: String, txn: OpaquePointer) -> UnsafeMutablePointer<Branch>? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        return youtput_read_ymap(output)
    }

    func nestedArray(key: String, txn: OpaquePointer) -> UnsafeMutablePointer<Branch>? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        return youtput_read_yarray(output)
    }

    func nestedText(key: String, txn: OpaquePointer) -> UnsafeMutablePointer<Branch>? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        return youtput_read_ytext(output)
    }

    // ─── Metadata ────────────────────────────────────────────────────────

    func length(txn: OpaquePointer) -> UInt32 {
        return ymap_len(branch, txn)
    }

    // ─── Iteration ───────────────────────────────────────────────────────

    func iterate(txn: OpaquePointer, body: (YrsMapEntry) -> Void) {
        guard let iter = ymap_iter(branch, txn) else { return }
        defer { ymap_iter_destroy(iter) }
        while let entry = ymap_iter_next(iter) {
            let wrapper = YrsMapEntry(entry)
            body(wrapper)
        }
    }
}
