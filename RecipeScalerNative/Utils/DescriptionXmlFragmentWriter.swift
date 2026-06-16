//
//  DescriptionXmlFragmentWriter.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore
import YrsC

enum DescriptionXmlFragmentWriter {
    static func apply(blocks: [DescriptionBlock], rawDoc: UnsafeMutablePointer<YDoc>, txn: OpaquePointer) {
        guard let fragment = ytype_get(txn, "description") else { return }

        var childIndex: UInt32 = 0
        var pendingListItems: [String] = []

        func flushList() {
            guard !pendingListItems.isEmpty else { return }
            guard let orderedList = yxmlelem_insert_elem(fragment, txn, childIndex, "orderedList") else {
                pendingListItems = []
                return
            }
            childIndex += 1
            for (index, item) in pendingListItems.enumerated() {
                guard let listItem = yxmlelem_insert_elem(orderedList, txn, UInt32(index), "listItem") else {
                    continue
                }
                insertParagraph(item, into: listItem, at: 0, txn: txn)
            }
            pendingListItems = []
        }

        for block in blocks {
            switch block {
            case let .paragraph(text):
                flushList()
                insertParagraph(text, into: fragment, at: childIndex, txn: txn)
                childIndex += 1
            case let .heading(level, text):
                flushList()
                insertHeading(text, level: level, into: fragment, at: childIndex, txn: txn)
                childIndex += 1
            case let .orderedListItem(text):
                pendingListItems.append(text)
            }
        }
        flushList()
    }

    private static func insertParagraph(
        _ text: String,
        into parent: UnsafeMutablePointer<Branch>,
        at index: UInt32,
        txn: OpaquePointer
    ) {
        guard let paragraph = yxmlelem_insert_elem(parent, txn, index, "paragraph") else { return }
        insertText(text, into: paragraph, txn: txn)
    }

    private static func insertHeading(
        _ text: String,
        level: Int,
        into parent: UnsafeMutablePointer<Branch>,
        at index: UInt32,
        txn: OpaquePointer
    ) {
        guard let heading = yxmlelem_insert_elem(parent, txn, index, "heading") else { return }
        let clamped = min(6, max(1, level))
        insertAttribute(key: "level", value: String(clamped), on: heading, txn: txn)
        insertText(text, into: heading, txn: txn)
    }

    private static func insertText(_ text: String, into element: UnsafeMutablePointer<Branch>, txn: OpaquePointer) {
        guard let textNode = yxmlelem_insert_text(element, txn, 0) else { return }
        text.withCString { cstr in
            yxmltext_insert(textNode, txn, 0, cstr, nil)
        }
    }

    private static func insertAttribute(
        key: String,
        value: String,
        on element: UnsafeMutablePointer<Branch>,
        txn: OpaquePointer
    ) {
        key.withCString { keyCString in
            value.withCString { valueCString in
                var input = yinput_string(valueCString)
                yxmlelem_insert_attr(element, txn, keyCString, &input)
            }
        }
    }
}
