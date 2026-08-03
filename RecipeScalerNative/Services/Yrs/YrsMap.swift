import Foundation
import YrsC

/// Read operations on a Y.Map shared type within a Y.Doc.
struct YrsMap {
    let branch: UnsafeMutablePointer<Branch>

    // ─── Primitive Reads ─────────────────────────────────────────────────

    func string(key: String, txn: OpaquePointer) -> String? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        let tag = output.pointee.tag
        guard tag == YrsValue.Y_JSON_STR else { return nil }
        guard let cStr = youtput_read_string(output) else { return nil }
        // Payload is freed by youtput_destroy; copy before returning.
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
        if let ptr = youtput_read_long(output) { return Int(ptr.pointee) }
        // Fallback: web stores some integer fields (e.g. ingredient.order) as Y_JSON_NUM.
        if let ptr = youtput_read_float(output) { return Int(ptr.pointee) }
        return nil
    }

    /// String, JSON number, or integer — as display text (web often stores `originalAmount` as number).
    func scalarString(key: String, txn: OpaquePointer) -> String? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        defer { youtput_destroy(output) }
        if output.pointee.tag == YrsValue.Y_JSON_STR, let cStr = youtput_read_string(output) {
            return String(cString: cStr)
        }
        if let ptr = youtput_read_float(output) {
            return IngredientData.formatScalarNumber(ptr.pointee)
        }
        if let ptr = youtput_read_long(output) {
            return IngredientData.formatScalarNumber(Double(ptr.pointee))
        }
        return nil
    }

    /// Whether the key is missing or explicitly null/undefined.
    func isNullOrMissing(key: String, txn: OpaquePointer) -> Bool {
        guard let output = ymap_get(branch, txn, key) else { return true }
        defer { youtput_destroy(output) }
        let tag = output.pointee.tag
        return tag == YrsValue.Y_JSON_NULL || tag == YrsValue.Y_UNDEFINED
    }

    /// Get the raw YrsValue for a key. Caller owns the returned value (destroyed in `deinit`).
    func value(key: String, txn: OpaquePointer) -> YrsValue? {
        guard let output = ymap_get(branch, txn, key) else { return nil }
        return YrsValue(output)
    }

    /// Read a JSON-array-of-strings primitive stored under `key`
    /// (e.g. recipe entry `folderIds`). Returns `[]` when the key is absent,
    /// null/undefined, or not a JSON array; non-string elements are skipped.
    ///
    /// This is distinct from a nested `Y.Array` shared type — the value is a
    /// plain `Y_JSON_ARR` payload on the map (matches web `getRecipeFolderIds`).
    func stringArray(key: String, txn: OpaquePointer) -> [String] {
        guard let output = ymap_get(branch, txn, key) else { return [] }
        defer { youtput_destroy(output) }
        guard output.pointee.tag == YrsValue.Y_JSON_ARR else { return [] }
        guard let arrayPtr = youtput_read_json_array(output) else { return [] }
        let count = Int(output.pointee.len)
        guard count > 0 else { return [] }
        var result: [String] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let element = arrayPtr.advanced(by: index)
            guard element.pointee.tag == YrsValue.Y_JSON_STR,
                  let cStr = youtput_read_string(element) else {
                continue
            }
            result.append(String(cString: cStr))
        }
        return result
    }

    /// Whether the key carries a JSON-array value (used by `folderIds` checks).
    func hasJSONArray(key: String, txn: OpaquePointer) -> Bool {
        guard let output = ymap_get(branch, txn, key) else { return false }
        defer { youtput_destroy(output) }
        return output.pointee.tag == YrsValue.Y_JSON_ARR
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

    // ─── Writes (Phase 3) ────────────────────────────────────────────────

    func insert(key: String, value: YrsInput, txn: OpaquePointer) {
        YrsInput.withMaterialized(value) { input in
            var input = input
            key.withCString { keyPtr in
                ymap_insert(branch, txn, keyPtr, &input)
            }
        }
    }

    @discardableResult
    func remove(key: String, txn: OpaquePointer) -> Bool {
        key.withCString { keyPtr in
            ymap_remove(branch, txn, keyPtr) != 0
        }
    }
}
