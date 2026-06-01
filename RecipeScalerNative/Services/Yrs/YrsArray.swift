import Foundation
import YrsC

/// Read operations on a Y.Array shared type within a Y.Doc.
struct YrsArray {
    let branch: UnsafeMutablePointer<Branch>

    func length(txn: OpaquePointer) -> UInt32 {
        return yarray_len(branch)
    }

    /// Get a YrsValue at the given index. Returns nil if index is out of bounds.
    func get(index: UInt32, txn: OpaquePointer) -> YrsValue? {
        guard let output = yarray_get(branch, txn, index) else { return nil }
        return YrsValue(output)
    }

    /// Invokes `body` with a nested Y.Map at `index` while its parent YOutput is alive.
    func withMap<T>(at index: UInt32, txn: OpaquePointer, _ body: (YrsMap) throws -> T) rethrows -> T? {
        guard let output = yarray_get(branch, txn, index) else { return nil }
        defer { youtput_destroy(output) }
        guard let mapBranch = youtput_read_ymap(output) else { return nil }
        return try body(YrsMap(branch: mapBranch))
    }

    /// Iterates array elements that are Y.Maps. Map branches are only valid during `body`.
    func forEachMap(txn: OpaquePointer, _ body: (YrsMap) throws -> Void) rethrows {
        guard let iter = yarray_iter(branch, txn) else { return }
        defer { yarray_iter_destroy(iter) }
        while let output = yarray_iter_next(iter) {
            if let mapBranch = youtput_read_ymap(output) {
                try body(YrsMap(branch: mapBranch))
            }
            youtput_destroy(output)
        }
    }

    /// Iterate all elements as YrsValue.
    func iterate(txn: OpaquePointer, body: (YrsValue) -> Void) {
        guard let iter = yarray_iter(branch, txn) else { return }
        defer { yarray_iter_destroy(iter) }
        while let output = yarray_iter_next(iter) {
            let value = YrsValue(output)
            body(value)
        }
    }

}
