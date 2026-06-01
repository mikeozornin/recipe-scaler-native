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

    /// Get a nested Y.Map at the given index.
    func getMap(index: UInt32, txn: OpaquePointer) -> YrsMap? {
        guard let output = yarray_get(branch, txn, index) else { return nil }
        defer { youtput_destroy(output) }
        guard let mapBranch = youtput_read_ymap(output) else { return nil }
        return YrsMap(branch: mapBranch)
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

    /// Iterate all elements that are Y.Map, skipping non-map entries.
    func iterateMaps(txn: OpaquePointer) -> [YrsMap] {
        guard let iter = yarray_iter(branch, txn) else { return [] }
        defer { yarray_iter_destroy(iter) }
        var maps: [YrsMap] = []
        while let output = yarray_iter_next(iter) {
            if let mapBranch = youtput_read_ymap(output) {
                maps.append(YrsMap(branch: mapBranch))
            }
            youtput_destroy(output)
        }
        return maps
    }
}
