//
//  YrsXmlFragment.swift
//  RecipeScalerNative
//
//  Wrapper over a root-level Y.XmlFragment branch obtained from
//  `ytype_get(txn, "description")` or `yxmlfragment(doc, "description")`.
//  All operations require an active transaction passed by the caller
//  (matches YrsMap / YrsArray / YrsText conventions).
//

import Foundation
import YrsC

/// Read/write operations on a root-level `Y.XmlFragment` shared type.
/// Obtained from `YrsDocument.xmlFragment(txn:name:)` or `YrsDocument.recipeMap(txn:)`
/// siblings. The branch pointer is owned by the document — this wrapper does
/// not call `ybranch_destroy` (same model as `YrsMap`/`YrsArray`/`YrsText`).
struct YrsXmlFragment {
    let branch: UnsafeMutablePointer<Branch>

    /// Number of direct child nodes (elements + text nodes).
    func childLen(txn: OpaquePointer) -> UInt32 {
        yxmlelem_child_len(branch, txn)
    }

    /// Get the child node at `index`. The returned `YrsXmlNode` wraps a branch
    /// pointer owned by the document (valid for the transaction duration); the
    /// intermediate `YOutput` is freed before this method returns.
    /// Returns `nil` if `index` is out of bounds.
    func child(at index: UInt32, txn: OpaquePointer) -> YrsXmlNode? {
        guard let output = yxmlelem_get(branch, txn, index) else { return nil }
        defer { youtput_destroy(UnsafeMutablePointer(mutating: output)) }
        return YrsXmlNode.from(output: output)
    }

    /// Get the child node at `index` while its parent `YOutput` is alive.
    /// `body` receives either a `YrsXmlElement` or a `YrsXmlText` depending on
    /// the child's tag. Returns `nil` if `index` is out of bounds.
    func withChild<T>(at index: UInt32, txn: OpaquePointer, _ body: (YrsXmlNode) throws -> T) rethrows -> T? {
        guard let output = yxmlelem_get(branch, txn, index) else { return nil }
        defer { youtput_destroy(UnsafeMutablePointer(mutating: output)) }
        guard let node = YrsXmlNode.from(output: output) else { return nil }
        return try body(node)
    }

    /// Insert a `Y.XmlElement` child at `index` with the given tag name.
    /// Returns the new element wrapper, or `nil` if FFI rejected the insert.
    @discardableResult
    func insertElem(at index: UInt32, name: String, txn: OpaquePointer) -> YrsXmlElement? {
        guard let inserted = name.withCString({ namePtr in
            yxmlelem_insert_elem(branch, txn, index, namePtr)
        }) else { return nil }
        return YrsXmlElement(branch: inserted)
    }

    /// Insert a `Y.XmlText` child at `index`. Returns the new text wrapper,
    /// or `nil` if FFI rejected the insert.
    @discardableResult
    func insertText(at index: UInt32, txn: OpaquePointer) -> YrsXmlText? {
        guard let inserted = yxmlelem_insert_text(branch, txn, index) else { return nil }
        return YrsXmlText(branch: inserted)
    }

    /// Remove `count` children starting at `index`.
    func removeRange(at index: UInt32, count: UInt32, txn: OpaquePointer) {
        yxmlelem_remove_range(branch, txn, index, count)
    }

    /// Read a string attribute. Returns `nil` if the attribute is missing or
    /// not a string.
    func getAttr(_ name: String, txn: OpaquePointer) -> String? {
        guard let output = name.withCString({ namePtr in
            yxmlelem_get_attr(branch, txn, namePtr)
        }) else { return nil }
        defer { youtput_destroy(output) }
        guard let cStr = youtput_read_string(output) else { return nil }
        return String(cString: cStr)
    }

    /// Insert (or replace) a string attribute.
    func insertAttr(key: String, value: String, txn: OpaquePointer) {
        key.withCString { keyPtr in
            value.withCString { valuePtr in
                var input = yinput_string(valuePtr)
                yxmlelem_insert_attr(branch, txn, keyPtr, &input)
            }
        }
    }

    /// Iterate attributes. Iterator resources are released when the returned
    /// sequence is dropped.
    func attrIter(txn: OpaquePointer) -> YrsXmlAttrIterator? {
        guard let iter = yxmlelem_attr_iter(branch, txn) else { return nil }
        return YrsXmlAttrIterator(iter: iter)
    }
}

/// A tagged union of a `Y.XmlElement` and a `Y.XmlText` returned from
/// `YrsXmlFragment.withChild` / `YrsXmlElement.withChild`.
enum YrsXmlNode {
    case element(YrsXmlElement)
    case text(YrsXmlText)

    static func from(output: UnsafePointer<YOutput>) -> YrsXmlNode? {
        switch output.pointee.tag {
        case YrsValue.Y_XML_ELEM:
            guard let branch = youtput_read_yxmlelem(UnsafeMutablePointer(mutating: output)) else {
                return nil
            }
            return .element(YrsXmlElement(branch: branch))
        case YrsValue.Y_XML_TEXT:
            guard let branch = youtput_read_yxmltext(UnsafeMutablePointer(mutating: output)) else {
                return nil
            }
            return .text(YrsXmlText(branch: branch))
        default:
            return nil
        }
    }
}

/// Shared insert operations for `Y.XmlElement` and `Y.XmlFragment` — both can
/// act as a parent container for child elements/text nodes and attributes.
/// Used by `DescriptionXmlFragmentWriter` / `RecipeDescriptionXmlFragmentWriter`
/// to treat root fragments and nested elements uniformly.
protocol YrsXmlContainer {
    func insertElem(at index: UInt32, name: String, txn: OpaquePointer) -> YrsXmlElement?
    func insertText(at index: UInt32, txn: OpaquePointer) -> YrsXmlText?
    func insertAttr(key: String, value: String, txn: OpaquePointer)
}

extension YrsXmlFragment: YrsXmlContainer {}
extension YrsXmlElement: YrsXmlContainer {}
