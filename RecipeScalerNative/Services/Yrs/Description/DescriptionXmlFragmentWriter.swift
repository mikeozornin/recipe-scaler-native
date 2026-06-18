//
//  DescriptionXmlFragmentWriter.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

enum DescriptionXmlFragmentWriter {
    static func apply(blocks: [DescriptionBlock], to fragment: YrsXmlFragment, txn: OpaquePointer) {
        var childIndex: UInt32 = 0
        var pendingListItems: [String] = []

        func flushList() {
            guard !pendingListItems.isEmpty else { return }
            guard let orderedList = fragment.insertElem(at: childIndex, name: "orderedList", txn: txn) else {
                pendingListItems = []
                return
            }
            childIndex += 1
            for (index, item) in pendingListItems.enumerated() {
                guard let listItem = orderedList.insertElem(at: UInt32(index), name: "listItem", txn: txn) else {
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
            case .prepTime, .cookTime, .durationMinutes, .difficulty:
                // Structural metadata signals — must be resolved into a
                // localized `.paragraph` by `DescriptionBlockLocalizer` before
                // reaching the writer. Reaching here is a pipeline bug;
                // silently skip rather than lose the rest of the description.
                continue
            }
        }
        flushList()
    }

    private static func insertParagraph(
        _ text: String,
        into parent: YrsXmlContainer,
        at index: UInt32,
        txn: OpaquePointer
    ) {
        guard let paragraph = parent.insertElem(at: index, name: "paragraph", txn: txn) else { return }
        insertText(text, into: paragraph, txn: txn)
    }

    private static func insertHeading(
        _ text: String,
        level: Int,
        into parent: YrsXmlContainer,
        at index: UInt32,
        txn: OpaquePointer
    ) {
        guard let heading = parent.insertElem(at: index, name: "heading", txn: txn) else { return }
        let clamped = min(6, max(1, level))
        heading.insertAttr(key: "level", value: String(clamped), txn: txn)
        insertText(text, into: heading, txn: txn)
    }

    private static func insertText(_ text: String, into element: YrsXmlElement, txn: OpaquePointer) {
        guard let textNode = element.insertText(at: 0, txn: txn) else { return }
        textNode.insert(at: 0, str: text, txn: txn)
    }
}
