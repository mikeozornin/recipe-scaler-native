//
//  YrsXmlAttrIterator.swift
//  RecipeScalerNative
//
//  RAII Sequence over Y.XmlElement / Y.XmlText attributes. Calls
//  `yxmlattr_iter_destroy` in `deinit` and `yxmlattr_destroy` on each yielded
//  attribute after the body returns (parity with YrsMap.iterate).
//

import Foundation
import YrsC

/// A single attribute yielded by `YrsXmlAttrIterator`. Owns the underlying
/// `YXmlAttr` and frees it in `deinit` (parity with `YrsMapEntry`).
final class YrsXmlAttr {
    private let attr: UnsafeMutablePointer<YXmlAttr>

    init(_ attr: UnsafeMutablePointer<YXmlAttr>) {
        self.attr = attr
    }

    deinit {
        yxmlattr_destroy(attr)
    }

    /// Attribute name (e.g. "href", "level", "data-timer-id").
    var name: String {
        guard let namePtr = attr.pointee.name else { return "" }
        return String(cString: namePtr)
    }

    /// Borrow the attribute's `YOutput` value for type-safe reads. Do not
    /// escape the pointer from `body` — it is freed when this `YrsXmlAttr`
    /// is deallocated.
    func withValue<T>(_ body: (UnsafePointer<YOutput>?) throws -> T) rethrows -> T {
        try body(attr.pointee.value)
    }

    /// Convenience: read the value as a string.
    func stringValue() -> String? {
        guard let value = attr.pointee.value else { return nil }
        guard let cStr = youtput_read_string(UnsafeMutablePointer(mutating: value)) else {
            return nil
        }
        // The C string is owned by the YOutput (freed in deinit) — copy now.
        return String(cString: cStr)
    }
}

/// RAII `Sequence` over `yxmlelem_attr_iter` / `yxmltext_attr_iter`. Calls
/// `yxmlattr_iter_destroy` in `deinit`. Each yielded `YrsXmlAttr` owns its
/// own `YXmlAttr` and is freed independently.
final class YrsXmlAttrIterator: Sequence {
    private let iter: UnsafeMutablePointer<YXmlAttrIter>
    private var consumed = false

    init(iter: UnsafeMutablePointer<YXmlAttrIter>) {
        self.iter = iter
    }

    deinit {
        yxmlattr_iter_destroy(iter)
    }

    func makeIterator() -> AnyIterator<YrsXmlAttr> {
        AnyIterator { [self] in
            // libyrs iterator is single-pass; guard against re-iteration.
            guard !consumed else { return nil }
            guard let next = yxmlattr_iter_next(iter) else {
                consumed = true
                return nil
            }
            return YrsXmlAttr(next)
        }
    }
}
