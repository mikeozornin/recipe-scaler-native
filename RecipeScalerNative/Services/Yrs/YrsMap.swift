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
        // String payload is freed by youtput_destroy (see libyrs.h youtput_read_string).
        return String(cString: cStr)
    }

    func bool(key: String, txn: OpaquePointer) -> Bool? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        if let ptr = youtput_read_bool(output) {
            return ptr.pointee != 0
        }
        // Yjs may encode booleans as JSON integers in some documents.
        if output.pointee.tag == YrsValue.Y_JSON_INT, let ptr = youtput_read_long(output) {
            return ptr.pointee != 0
        }
        return nil
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

    /// Get the raw YrsValue for a key. Caller owns the returned value (destroyed in `deinit`).
    func value(key: String, txn: OpaquePointer) -> YrsValue? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        return YrsValue(output)
    }

    // ─── Nested Type Reads ───────────────────────────────────────────────

    func withNestedMap<T>(key: String, txn: OpaquePointer, _ body: (YrsMap) throws -> T) rethrows -> T? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        guard let mapBranch = youtput_read_ymap(output) else { return nil }
        return try body(YrsMap(branch: mapBranch))
    }

    func withNestedArray<T>(key: String, txn: OpaquePointer, _ body: (YrsArray) throws -> T) rethrows -> T? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        guard let arrayBranch = youtput_read_yarray(output) else { return nil }
        return try body(YrsArray(branch: arrayBranch))
    }

    func withNestedText<T>(key: String, txn: OpaquePointer, _ body: (YrsText) throws -> T) rethrows -> T? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        guard let textBranch = youtput_read_ytext(output) else { return nil }
        return try body(YrsText(branch: textBranch))
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
