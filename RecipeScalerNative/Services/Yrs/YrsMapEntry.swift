import Foundation
import YrsC

/// A single entry from iterating a Y.Map, containing a key and its value.
/// Owns the underlying YMapEntry and frees it in deinit.
final class YrsMapEntry {
    private let entry: UnsafeMutablePointer<YMapEntry>

    init(_ entry: UnsafeMutablePointer<YMapEntry>) {
        self.entry = entry
    }

    deinit {
        ymap_entry_destroy(entry)
    }

    /// The entry's key as a Swift string.
    var key: String {
        return String(cString: entry.pointee.key)
    }

    /// The entry's value as a YrsValue wrapper.
    /// Note: YMapEntry.value is `const YOutput*`, so we create a mutable copy.
    var value: YrsValue {
        // youtput_read_* functions take `const struct YOutput*` — we can pass
        // the const pointer directly to YrsValue which takes a mutable pointer.
        // Since YrsMapEntry owns the entry and ymap_entry_destroy frees the entry
        // (not the output), we need to be careful. The output pointer is owned by
        // the YMapEntry — so we should NOT destroy it separately.
        let constPtr = entry.pointee.value
        return YrsValue(UnsafeMutablePointer(mutating: constPtr!))
    }
}
