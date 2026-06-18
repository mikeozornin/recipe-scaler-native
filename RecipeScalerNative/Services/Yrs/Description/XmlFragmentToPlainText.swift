//
//  XmlFragmentToPlainText.swift
//  RecipeScalerNative
//
//  One-pass Y.XmlFragment → plain text for search/Spotlight (no HTML, no regex).
//

import Foundation

enum XmlFragmentToPlainText {
    private static let maxNodes = 4_000
    private static let maxDepth = 32

    /// Bounded tree walk inside an existing read transaction.
    static func plainText(from fragment: YrsXmlFragment, txn: OpaquePointer) -> String {
        let childCount = fragment.childLen(txn: txn)
        guard childCount > 0 else { return "" }

        var parts: [String] = []
        parts.reserveCapacity(Int(min(childCount, 64)))
        var budget = maxNodes

        for index in 0..<childCount {
            guard budget > 0 else { break }
            guard let node = fragment.child(at: index, txn: txn) else { continue }
            if let piece = renderNode(node, txn: txn, depth: 0, budget: &budget) {
                let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
            }
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Bounded FFI walk

    private static func renderNode(
        _ node: YrsXmlNode,
        txn: OpaquePointer,
        depth: Int,
        budget: inout Int
    ) -> String? {
        guard budget > 0, depth <= maxDepth else { return nil }
        budget -= 1

        switch node {
        case let .element(elem):
            let tag = elem.tag(txn: txn)
            let inner = renderChildren(of: elem, txn: txn, depth: depth + 1, budget: &budget)
            return wrapElement(tag: tag, element: elem, txn: txn, inner: inner)
        case let .text(text):
            return renderXmlText(text, txn: txn)
        }
    }

    private static func renderChildren(
        of element: YrsXmlElement,
        txn: OpaquePointer,
        depth: Int,
        budget: inout Int
    ) -> String {
        guard budget > 0, depth <= maxDepth else { return "" }
        let count = element.childLen(txn: txn)
        guard count > 0 else { return "" }

        var parts: [String] = []
        for index in 0..<count {
            guard budget > 0 else { break }
            guard let node = element.child(at: index, txn: txn) else { continue }
            if let piece = renderNode(node, txn: txn, depth: depth + 1, budget: &budget), !piece.isEmpty {
                parts.append(piece)
            }
        }
        return parts.joined()
    }

    private static func wrapElement(
        tag: String,
        element: YrsXmlElement,
        txn: OpaquePointer,
        inner: String
    ) -> String {
        switch tag {
        case "hardBreak":
            return " "
        case "horizontalRule":
            return ""
        case "timer":
            if !inner.isEmpty { return inner }
            return timerFallbackLabel(from: element, txn: txn)
        case "ingredient":
            if let amount = element.getAttr("data-original-amount", txn: txn),
               !amount.isEmpty {
                return amount
            }
            return inner
        case "paragraph", "listItem", "heading", "blockquote", "codeBlock",
             "bulletList", "orderedList", "bold", "italic", "strike", "highlight", "code",
             "link", "a":
            return inner
        default:
            return inner
        }
    }

    private static func renderXmlText(_ text: YrsXmlText, txn: OpaquePointer) -> String? {
        if let chunks = text.withChunks(txn: txn, { chunks in
            var parts: [String] = []
            parts.reserveCapacity(Int(chunks.count))
            for index in 0..<chunks.count {
                guard let str = chunks.string(at: index), !str.isEmpty else { continue }
                parts.append(str)
            }
            let joined = parts.joined()
            return joined.isEmpty ? nil : joined
        }) ?? nil {
            return chunks
        }

        guard let str = text.string(txn: txn) else { return nil }
        return str.isEmpty ? nil : str
    }

    private static func timerFallbackLabel(from element: YrsXmlElement, txn: OpaquePointer) -> String {
        if let value = element.getAttr("data-value", txn: txn),
           let unit = element.getAttr("data-type", txn: txn) {
            return "\(value) \(unit)"
        }
        return ""
    }
}
