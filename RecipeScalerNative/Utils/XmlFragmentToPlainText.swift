//
//  XmlFragmentToPlainText.swift
//  RecipeScalerNative
//
//  One-pass Y.XmlFragment → plain text for search/Spotlight (no HTML, no regex).
//

import Foundation
import YrsC

enum XmlFragmentToPlainText {
    private static let maxNodes = 4_000
    private static let maxDepth = 32

    /// Bounded tree walk inside an existing read transaction.
    static func plainText(txn: OpaquePointer) -> String {
        guard let fragment = ytype_get(txn, "description") else { return "" }
        let childCount = yxmlelem_child_len(fragment, txn)
        guard childCount > 0 else { return "" }

        var parts: [String] = []
        parts.reserveCapacity(Int(min(childCount, 64)))
        var budget = maxNodes

        for index in 0..<childCount {
            guard budget > 0 else { break }
            guard let output = yxmlelem_get(fragment, txn, index) else { continue }
            if let piece = renderNode(output, txn: txn, depth: 0, budget: &budget) {
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
        _ output: UnsafePointer<YOutput>,
        txn: OpaquePointer,
        depth: Int,
        budget: inout Int
    ) -> String? {
        guard budget > 0, depth <= maxDepth else { return nil }
        budget -= 1

        switch output.pointee.tag {
        case YrsValue.Y_XML_ELEM:
            guard let branch = youtput_read_yxmlelem(UnsafeMutablePointer(mutating: output)) else {
                return nil
            }
            let tag = elementTag(branch)
            let inner = renderChildren(of: branch, txn: txn, depth: depth + 1, budget: &budget)
            return wrapElement(tag: tag, branch: branch, txn: txn, inner: inner)
        case YrsValue.Y_XML_TEXT:
            guard let branch = youtput_read_yxmltext(UnsafeMutablePointer(mutating: output)) else {
                return nil
            }
            return renderXmlText(branch, txn: txn)
        default:
            return nil
        }
    }

    private static func renderChildren(
        of branch: UnsafeMutablePointer<Branch>,
        txn: OpaquePointer,
        depth: Int,
        budget: inout Int
    ) -> String {
        guard budget > 0, depth <= maxDepth else { return "" }
        let count = yxmlelem_child_len(branch, txn)
        guard count > 0 else { return "" }

        var parts: [String] = []
        for index in 0..<count {
            guard budget > 0 else { break }
            guard let output = yxmlelem_get(branch, txn, index) else { continue }
            if let piece = renderNode(output, txn: txn, depth: depth + 1, budget: &budget), !piece.isEmpty {
                parts.append(piece)
            }
        }
        return parts.joined()
    }

    private static func wrapElement(
        tag: String,
        branch: UnsafeMutablePointer<Branch>,
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
            return timerFallbackLabel(from: branch, txn: txn)
        case "ingredient":
            if let amount = elementAttribute(branch: branch, txn: txn, name: "data-original-amount"),
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

    private static func renderXmlText(_ branch: UnsafeMutablePointer<Branch>, txn: OpaquePointer) -> String? {
        var chunkCount: UInt32 = 0
        if let chunks = ytext_chunks(branch, txn, &chunkCount), chunkCount > 0 {
            defer { ychunks_destroy(chunks, chunkCount) }
            var parts: [String] = []
            parts.reserveCapacity(Int(chunkCount))
            for index in 0..<chunkCount {
                let chunk = chunks[Int(index)]
                guard let text = stringFromOutput(chunk.data), !text.isEmpty else { continue }
                parts.append(text)
            }
            let joined = parts.joined()
            if !joined.isEmpty { return joined }
        }

        guard let cStr = yxmltext_string(branch, txn) else { return nil }
        defer { ystring_destroy(cStr) }
        let text = String(cString: cStr)
        return text.isEmpty ? nil : text
    }

    private static func stringFromOutput(_ output: YOutput) -> String? {
        withUnsafePointer(to: output) { ptr in
            guard let cStr = youtput_read_string(ptr) else { return nil }
            return String(cString: cStr)
        }
    }

    private static func elementAttribute(
        branch: UnsafeMutablePointer<Branch>,
        txn: OpaquePointer,
        name: String
    ) -> String? {
        guard let output = yxmlelem_get_attr(branch, txn, name) else { return nil }
        defer { youtput_destroy(output) }
        guard let cStr = youtput_read_string(output) else { return nil }
        return String(cString: cStr)
    }

    private static func timerFallbackLabel(from branch: UnsafeMutablePointer<Branch>, txn: OpaquePointer) -> String {
        if let value = elementAttribute(branch: branch, txn: txn, name: "data-value"),
           let unit = elementAttribute(branch: branch, txn: txn, name: "data-type") {
            return "\(value) \(unit)"
        }
        return ""
    }

    private static func elementTag(_ branch: UnsafeMutablePointer<Branch>) -> String {
        guard let cStr = yxmlelem_tag(branch) else { return "" }
        return String(cString: cStr)
    }
}
