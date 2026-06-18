//
//  RecipeDescriptionXmlFragmentWriter.swift
//  RecipeScalerNative
//
//  Builds a Y.XmlFragment from `RecipeDescriptionDocument` (parsed HTML) so that
//  imported recipes (native .json/.zip format) round-trip with the same structure
//  as the web Tiptap/y-prosemirror editor.
//
//  Mirrors the reader `XmlFragmentToHTML.wrapElement` (Utils/XmlFragmentToHTML.swift)
//  and follows the canonical node model described in
//  specs/019-recipe-description-inline-edit/contracts/description-markup-parity.md.
//

import Foundation

enum RecipeDescriptionXmlFragmentWriter {
    /// Writes the parsed description as a Y.XmlFragment rooted at the given fragment.
    /// Replaces any existing content.
    static func apply(document: RecipeDescriptionDocument, to fragment: YrsXmlFragment, txn: OpaquePointer) {
        // Drop any pre-existing children before inserting (defensive: import path always operates on a fresh doc).
        let existing = fragment.childLen(txn: txn)
        if existing > 0 {
            fragment.removeRange(at: 0, count: existing, txn: txn)
        }

        var childIndex: UInt32 = 0
        var pendingSteps: [[RecipeDescriptionInlineRun]] = []
        var pendingBullets: [[RecipeDescriptionInlineRun]] = []

        func flushOrdered() {
            guard !pendingSteps.isEmpty else { return }
            guard let orderedList = fragment.insertElem(at: childIndex, name: "orderedList", txn: txn) else {
                pendingSteps.removeAll()
                return
            }
            childIndex += 1
            for (index, runs) in pendingSteps.enumerated() {
                guard let listItem = orderedList.insertElem(at: UInt32(index), name: "listItem", txn: txn) else { continue }
                insertParagraph(runs: runs, into: listItem, at: 0, txn: txn)
            }
            pendingSteps.removeAll()
        }

        func flushBullets() {
            guard !pendingBullets.isEmpty else { return }
            guard let bulletList = fragment.insertElem(at: childIndex, name: "bulletList", txn: txn) else {
                pendingBullets.removeAll()
                return
            }
            childIndex += 1
            for (index, runs) in pendingBullets.enumerated() {
                guard let listItem = bulletList.insertElem(at: UInt32(index), name: "listItem", txn: txn) else { continue }
                insertParagraph(runs: runs, into: listItem, at: 0, txn: txn)
            }
            pendingBullets.removeAll()
        }

        for block in document.blocks {
            switch block {
            case .paragraph(_, let runs):
                flushOrdered()
                flushBullets()
                insertParagraph(runs: runs, into: fragment, at: childIndex, txn: txn)
                childIndex += 1
            case .heading(_, let level, let runs):
                flushOrdered()
                flushBullets()
                insertHeading(runs: runs, level: level, into: fragment, at: childIndex, txn: txn)
                childIndex += 1
            case .orderedStep:
                flushBullets()
                let runs = extractedRuns(from: block)
                pendingSteps.append(runs)
            case .bullet:
                flushOrdered()
                let runs = extractedRuns(from: block)
                pendingBullets.append(runs)
            }
        }
        flushOrdered()
        flushBullets()
    }

    // MARK: - Block nodes

    private static func insertParagraph(
        runs: [RecipeDescriptionInlineRun],
        into parent: YrsXmlContainer,
        at index: UInt32,
        txn: OpaquePointer
    ) {
        guard let paragraph = parent.insertElem(at: index, name: "paragraph", txn: txn) else { return }
        appendInlineRuns(runs, into: paragraph, txn: txn)
    }

    private static func insertHeading(
        runs: [RecipeDescriptionInlineRun],
        level: Int,
        into parent: YrsXmlContainer,
        at index: UInt32,
        txn: OpaquePointer
    ) {
        guard let heading = parent.insertElem(at: index, name: "heading", txn: txn) else { return }
        let clamped = min(6, max(1, level))
        heading.insertAttr(key: "level", value: String(clamped), txn: txn)
        appendInlineRuns(runs, into: heading, txn: txn)
    }

    private static func extractedRuns(from block: RecipeDescriptionBlock) -> [RecipeDescriptionInlineRun] {
        switch block {
        case .paragraph(_, let runs),
             .bullet(_, let runs):
            return runs
        case .orderedStep(_, _, let runs),
             .heading(_, _, let runs):
            return runs
        }
    }

    // MARK: - Inline runs (text + nested inline elements)

    private static func appendInlineRuns(
        _ runs: [RecipeDescriptionInlineRun],
        into parent: YrsXmlElement,
        txn: OpaquePointer
    ) {
        var textChildIndex: UInt32 = 0
        for run in runs {
            switch run {
            case .plain(let text):
                textChildIndex = appendText(text, into: parent, at: textChildIndex, txn: txn)
            case .strong(let text):
                textChildIndex = appendNestedMark(tag: "bold", text: text, into: parent, at: textChildIndex, txn: txn)
            case .em(let text):
                textChildIndex = appendNestedMark(tag: "italic", text: text, into: parent, at: textChildIndex, txn: txn)
            case .link(let url, let text):
                textChildIndex = appendLink(url: url, text: text, into: parent, at: textChildIndex, txn: txn)
            case .timer(let reference):
                textChildIndex = appendTimer(reference: reference, into: parent, at: textChildIndex, txn: txn)
            case .ingredient(let id, let ratio, let originalAmount, let text):
                textChildIndex = appendIngredient(
                    id: id,
                    ratio: ratio,
                    originalAmount: originalAmount,
                    fallbackText: text,
                    into: parent,
                    at: textChildIndex,
                    txn: txn
                )
            case .lineBreak:
                appendSelfClosing(tag: "hardBreak", into: parent, at: textChildIndex, txn: txn)
                textChildIndex += 1
            }
        }
    }

    /// Plain text in the paragraph's child text node (inserted at the current child index).
    /// If the previous child is a `Y.XmlText`, append to it; otherwise create a new text child.
    @discardableResult
    private static func appendText(
        _ text: String,
        into parent: YrsXmlElement,
        at index: UInt32,
        txn: OpaquePointer
    ) -> UInt32 {
        guard !text.isEmpty else { return index }
        // Create a dedicated text node at `index` for the run — matches ProseMirror's one-text-per-run
        // pattern produced by y-prosemirror when multiple marks/elements are interleaved.
        guard let textNode = parent.insertText(at: index, txn: txn) else { return index }
        textNode.insert(at: 0, str: text, txn: txn)
        return index + 1
    }

    @discardableResult
    private static func appendNestedMark(
        tag: String,
        text: String,
        into parent: YrsXmlElement,
        at index: UInt32,
        txn: OpaquePointer
    ) -> UInt32 {
        guard !text.isEmpty else { return index }
        guard let mark = parent.insertElem(at: index, name: tag, txn: txn) else { return index }
        if let textNode = mark.insertText(at: 0, txn: txn) {
            textNode.insert(at: 0, str: text, txn: txn)
        }
        return index + 1
    }

    @discardableResult
    private static func appendLink(
        url: String,
        text: String,
        into parent: YrsXmlElement,
        at index: UInt32,
        txn: OpaquePointer
    ) -> UInt32 {
        guard !text.isEmpty else { return index }
        let href = url.isEmpty ? text : url
        guard let link = parent.insertElem(at: index, name: "link", txn: txn) else { return index }
        link.insertAttr(key: "href", value: href, txn: txn)
        if let textNode = link.insertText(at: 0, txn: txn) {
            textNode.insert(at: 0, str: text, txn: txn)
        }
        return index + 1
    }

    /// Timer node: contains the display text (per `description-markup-parity.md` § Timer).
    @discardableResult
    private static func appendTimer(
        reference: RecipeDescriptionTimerReference,
        into parent: YrsXmlElement,
        at index: UInt32,
        txn: OpaquePointer
    ) -> UInt32 {
        guard let timer = parent.insertElem(at: index, name: "timer", txn: txn) else { return index }
        timer.insertAttr(key: "data-duration", value: String(reference.durationSeconds), txn: txn)
        timer.insertAttr(key: "data-type", value: reference.type.rawValue, txn: txn)
        if let name = reference.name, !name.isEmpty {
            timer.insertAttr(key: "data-name", value: name, txn: txn)
        }
        let valueString = reference.valueAttribute
        if !valueString.isEmpty {
            timer.insertAttr(key: "data-value", value: valueString, txn: txn)
        }
        if let textNode = timer.insertText(at: 0, txn: txn) {
            textNode.insert(at: 0, str: reference.displayText, txn: txn)
        }
        return index + 1
    }

    /// Ingredient node (v3 canonical: atom-style element with attrs; no child text).
    /// Falls back to embedding the display text if no `data-original-amount` is available,
    /// so legacy readers that rely on the inner text still see a value.
    @discardableResult
    private static func appendIngredient(
        id: String?,
        ratio: Double?,
        originalAmount: String?,
        fallbackText: String,
        into parent: YrsXmlElement,
        at index: UInt32,
        txn: OpaquePointer
    ) -> UInt32 {
        guard let ingredient = parent.insertElem(at: index, name: "ingredient", txn: txn) else { return index }
        if let id, !id.isEmpty {
            ingredient.insertAttr(key: "data-ingredient-id", value: id, txn: txn)
        }
        if let ratio {
            ingredient.insertAttr(key: "data-ratio", value: formatAmount(ratio), txn: txn)
        }
        if let originalAmount, !originalAmount.isEmpty {
            ingredient.insertAttr(key: "data-original-amount", value: originalAmount, txn: txn)
        }
        // Some readers (XmlFragmentToHTML.wrapElement:215) fall back to inner text when
        // data-original-amount is absent — preserve display text in that case.
        if (originalAmount == nil || originalAmount?.isEmpty == true), !fallbackText.isEmpty {
            if let textNode = ingredient.insertText(at: 0, txn: txn) {
                textNode.insert(at: 0, str: fallbackText, txn: txn)
            }
        }
        return index + 1
    }

    @discardableResult
    private static func appendSelfClosing(
        tag: String,
        into parent: YrsXmlElement,
        at index: UInt32,
        txn: OpaquePointer
    ) -> UInt32 {
        guard parent.insertElem(at: index, name: tag, txn: txn) != nil else { return index }
        return index + 1
    }

    // MARK: - Helpers

    private static func formatAmount(_ value: Double) -> String {
        // TP14 [review #14]: guard NaN/Inf and out-of-Int64 range before cast.
        guard value.isFinite else { return "" }
        if value.rounded(.towardZero) == value, let intValue = Int(exactlySafe: value.rounded()) {
            return String(intValue)
        }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
