//
//  YrsXmlElement.swift
//  RecipeScalerNative
//
//  Wrapper over a child Y.XmlElement branch (e.g. <paragraph>, <heading>,
//  <bulletList>). Same lifetime model as YrsXmlFragment — the branch is owned
//  by the document; this wrapper does not destroy it.
//

import Foundation
import YrsC

/// Read operations on a `Y.XmlElement` child node.
struct YrsXmlElement {
    let branch: UnsafeMutablePointer<Branch>

    /// Element tag name (e.g. "paragraph", "heading"). Empty string for the
    /// root-level `<UNDEFINED>` fragment.
    func tag(txn: OpaquePointer) -> String {
        guard let cStr = yxmlelem_tag(branch) else { return "" }
        // yxmlelem_tag returns a C string that the caller must release with
        // ystring_destroy.
        defer { ystring_destroy(cStr) }
        return String(cString: cStr)
    }

    /// Number of direct child nodes.
    func childLen(txn: OpaquePointer) -> UInt32 {
        yxmlelem_child_len(branch, txn)
    }

    /// Get the child node at `index`. The returned `YrsXmlNode` wraps a branch
    /// pointer owned by the document (valid for the transaction duration); the
    /// intermediate `YOutput` is freed before this method returns.
    func child(at index: UInt32, txn: OpaquePointer) -> YrsXmlNode? {
        guard let output = yxmlelem_get(branch, txn, index) else { return nil }
        defer { youtput_destroy(UnsafeMutablePointer(mutating: output)) }
        return YrsXmlNode.from(output: output)
    }

    /// Get the child node at `index` while its parent `YOutput` is alive.
    func withChild<T>(at index: UInt32, txn: OpaquePointer, _ body: (YrsXmlNode) throws -> T) rethrows -> T? {
        guard let output = yxmlelem_get(branch, txn, index) else { return nil }
        defer { youtput_destroy(UnsafeMutablePointer(mutating: output)) }
        guard let node = YrsXmlNode.from(output: output) else { return nil }
        return try body(node)
    }

    /// Read a string attribute.
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

    /// Insert a `Y.XmlElement` child at `index` with the given tag.
    @discardableResult
    func insertElem(at index: UInt32, name: String, txn: OpaquePointer) -> YrsXmlElement? {
        guard let inserted = name.withCString({ namePtr in
            yxmlelem_insert_elem(branch, txn, index, namePtr)
        }) else { return nil }
        return YrsXmlElement(branch: inserted)
    }

    /// Insert a `Y.XmlText` child at `index`.
    @discardableResult
    func insertText(at index: UInt32, txn: OpaquePointer) -> YrsXmlText? {
        guard let inserted = yxmlelem_insert_text(branch, txn, index) else { return nil }
        return YrsXmlText(branch: inserted)
    }

    /// Remove `count` children starting at `index`.
    func removeRange(at index: UInt32, count: UInt32, txn: OpaquePointer) {
        yxmlelem_remove_range(branch, txn, index, count)
    }
}
