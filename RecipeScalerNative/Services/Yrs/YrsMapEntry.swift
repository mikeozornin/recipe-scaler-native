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

    func stringValue() -> String? {
        guard let output = entry.pointee.value else { return nil }
        guard let cStr = youtput_read_string(output) else { return nil }
        return String(cString: cStr)
    }

    func boolValue() -> Bool? {
        guard let output = entry.pointee.value else { return nil }
        guard let ptr = youtput_read_bool(output) else { return nil }
        return ptr.pointee != 0
    }

    func intValue() -> Int? {
        guard let output = entry.pointee.value else { return nil }
        guard let ptr = youtput_read_long(output) else { return nil }
        return Int(ptr.pointee)
    }

    func doubleValue() -> Double? {
        guard let output = entry.pointee.value else { return nil }
        guard let ptr = youtput_read_float(output) else { return nil }
        return ptr.pointee
    }

    var tag: Int8 {
        entry.pointee.value?.pointee.tag ?? YrsValue.Y_UNDEFINED
    }
}
