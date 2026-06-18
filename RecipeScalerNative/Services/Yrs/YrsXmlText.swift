//
//  YrsXmlText.swift
//  RecipeScalerNative
//
//  Wrapper over a Y.XmlText branch (inline text with formatting chunks and
//  attributes, used by ProseMirror/y-prosemirror). Same lifetime model as
//  YrsXmlFragment — the branch is owned by the document; this wrapper does
//  not destroy it. The chunks buffer returned by `chunks(txn:)` IS owned by
//  the caller and is released via YrsXmlChunks's `deinit`.
//

import Foundation
import YrsC

/// Read operations on a `Y.XmlText` child node.
struct YrsXmlText {
    let branch: UnsafeMutablePointer<Branch>

    /// Full string content. Returns `nil` if FFI returns no string.
    func string(txn: OpaquePointer) -> String? {
        guard let cStr = yxmltext_string(branch, txn) else { return nil }
        defer { ystring_destroy(cStr) }
        return String(cString: cStr)
    }

    /// Length in bytes (without the null terminator).
    func length(txn: OpaquePointer) -> UInt32 {
        yxmltext_len(branch, txn)
    }

    /// Read a string attribute (e.g. `href` on a link-marked text node).
    func getAttr(_ name: String, txn: OpaquePointer) -> String? {
        guard let output = name.withCString({ namePtr in
            yxmltext_get_attr(branch, txn, namePtr)
        }) else { return nil }
        defer { youtput_destroy(output) }
        guard let cStr = youtput_read_string(output) else { return nil }
        return String(cString: cStr)
    }

    /// Iterate attributes (e.g. link marks stored as `link`/`link--*` attrs).
    func attrIter(txn: OpaquePointer) -> YrsXmlAttrIterator? {
        guard let iter = yxmltext_attr_iter(branch, txn) else { return nil }
        return YrsXmlAttrIterator(iter: iter)
    }

    /// Borrow the delta chunks for the duration of `body`. The chunks buffer
    /// is freed automatically when the body returns (RAII via `YrsXmlChunks`).
    /// Each `YChunk` carries the text payload (`data`) and a list of
    /// formatting entries (`fmt`, `fmt_len`) — marks like `bold`, `italic`,
    /// `link` with their attribute payloads.
    func withChunks<T>(txn: OpaquePointer, _ body: (YrsXmlChunks) throws -> T) rethrows -> T? {
        var chunkCount: UInt32 = 0
        guard let chunksPtr = ytext_chunks(branch, txn, &chunkCount), chunkCount > 0 else {
            return nil
        }
        let owned = YrsXmlChunks(buffer: chunksPtr, count: chunkCount)
        return try body(owned)
    }

    /// Insert text at `index`. The string is copied by yrs; no ownership
    /// transfer for `str`.
    func insert(at index: UInt32, str: String, txn: OpaquePointer) {
        str.withCString { cstr in
            yxmltext_insert(branch, txn, index, cstr, nil)
        }
    }

    /// Insert (or replace) a string attribute.
    func insertAttr(key: String, value: String, txn: OpaquePointer) {
        key.withCString { keyPtr in
            value.withCString { valuePtr in
                var input = yinput_string(valuePtr)
                yxmltext_insert_attr(branch, txn, keyPtr, &input)
            }
        }
    }
}

/// RAII wrapper over the `YChunk` buffer returned by `ytext_chunks`. Calls
/// `ychunks_destroy` in `deinit`. Iterate via `subscript` or `forEach`.
final class YrsXmlChunks {
    let buffer: UnsafeMutablePointer<YChunk>
    let count: UInt32

    init(buffer: UnsafeMutablePointer<YChunk>, count: UInt32) {
        self.buffer = buffer
        self.count = count
    }

    deinit {
        ychunks_destroy(buffer, count)
    }

    subscript(_ index: UInt32) -> YChunk {
        precondition(index < count, "YrsXmlChunks index out of bounds")
        return buffer[Int(index)]
    }

    func forEach(_ body: (YChunk) throws -> Void) rethrows {
        for index in 0..<count {
            try body(buffer[Int(index)])
        }
    }

    /// Read the chunk's text payload as a Swift String. Returns `nil` if the
    /// payload is not a string (e.g. an embedded object or shared type).
    func string(at index: UInt32) -> String? {
        let chunk = self[index]
        return withUnsafePointer(to: chunk.data) { ptr in
            guard let cStr = youtput_read_string(ptr) else { return nil }
            return String(cString: cStr)
        }
    }

    /// Borrow the formatting entries for a chunk as an unsafe buffer pointer.
    /// The buffer is owned by the chunk (freed in `deinit`); do not escape the
    /// pointer from `body`.
    func withFormatEntries<T>(at index: UInt32, _ body: (UnsafePointer<YMapEntry>?, UInt32) throws -> T) rethrows -> T {
        let chunk = self[index]
        return try body(chunk.fmt, chunk.fmt_len)
    }
}
