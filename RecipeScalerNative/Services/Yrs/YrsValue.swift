import Foundation
import YrsC

/// Swift wrapper around yrs YOutput value, providing type-safe access to CRDT values.
///
/// Memory is managed automatically — `youtput_destroy` is called in `deinit`.
final class YrsValue {
    private let output: UnsafeMutablePointer<YOutput>

    /// Tag constants matching the yrs C API defines.
    static let Y_JSON: Int8 = -9
    static let Y_JSON_BOOL: Int8 = -8
    static let Y_JSON_NUM: Int8 = -7
    static let Y_JSON_INT: Int8 = -6
    static let Y_JSON_STR: Int8 = -5
    static let Y_JSON_BUF: Int8 = -4
    static let Y_JSON_ARR: Int8 = -3
    static let Y_JSON_MAP: Int8 = -2
    static let Y_JSON_NULL: Int8 = -1
    static let Y_JSON_UNDEF: Int8 = 0
    static let Y_ARRAY: Int8 = 1
    static let Y_MAP: Int8 = 2
    static let Y_TEXT: Int8 = 3
    static let Y_XML_ELEM: Int8 = 4
    static let Y_XML_TEXT: Int8 = 5
    static let Y_XML_FRAG: Int8 = 6
    static let Y_DOC: Int8 = 7
    static let Y_WEAK_LINK: Int8 = 8
    static let Y_UNDEFINED: Int8 = 9

    init(_ output: UnsafeMutablePointer<YOutput>) {
        self.output = output
    }

    deinit {
        youtput_destroy(output)
    }

    /// The raw tag value from yrs.
    var tag: Int8 {
        return output.pointee.tag
    }

    /// Read as a string (Y_JSON_STR).
    var stringValue: String? {
        guard let cStr = youtput_read_string(output) else { return nil }
        defer { ystring_destroy(cStr) }
        return String(cString: cStr)
    }

    /// Read as a boolean (Y_JSON_BOOL).
    var boolValue: Bool? {
        guard let ptr = youtput_read_bool(output) else { return nil }
        return ptr.pointee != 0
    }

    /// Read as a double (Y_JSON_NUM).
    var doubleValue: Double? {
        guard let ptr = youtput_read_float(output) else { return nil }
        return ptr.pointee
    }

    /// Read as an integer (Y_JSON_INT).
    var intValue: Int? {
        guard let ptr = youtput_read_long(output) else { return nil }
        return Int(ptr.pointee)
    }

    /// Read as a nested Y.Array branch (Y_ARRAY).
    var arrayBranch: UnsafeMutablePointer<Branch>? {
        return youtput_read_yarray(output)
    }

    /// Read as a nested Y.Map branch (Y_MAP).
    var mapBranch: UnsafeMutablePointer<Branch>? {
        return youtput_read_ymap(output)
    }

    /// Read as a nested Y.Text branch (Y_TEXT).
    var textBranch: UnsafeMutablePointer<Branch>? {
        return youtput_read_ytext(output)
    }
}
