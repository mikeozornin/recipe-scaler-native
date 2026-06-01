import Foundation
import YrsC

/// Read operations on a Y.Text shared type within a Y.Doc.
struct YrsText {
    let branch: UnsafeMutablePointer<Branch>

    func string(txn: OpaquePointer) -> String? {
        guard let cStr = ytext_string(branch, txn) else { return nil }
        defer { ystring_destroy(cStr) }
        return String(cString: cStr)
    }

    func length(txn: OpaquePointer) -> UInt32 {
        return ytext_len(branch, txn)
    }
}
