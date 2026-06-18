//
//  XmlFragmentToHTML.swift
//  RecipeScalerNative
//
//  Read-only v3 description: Y.XmlFragment → HTML for StepsSection (no Tiptap).
//  Never calls `yxmlelem_string` (can hang on large ProseMirror subtrees in yrs FFI).
//

import Foundation
import YrsC

enum XmlFragmentToHTML {
    private static let maxNodes = 4_000
    private static let maxDepth = 32

    /// Bounded tree walk inside an existing read transaction.
    /// Uses `ytype_get(txn,)` — never `yxmlfragment(doc,)` while a txn is open (deadlocks in yrs FFI).
    static func serializedFragment(txn: OpaquePointer) -> String? {
        guard let fragment = ytype_get(txn, "description") else { return nil }
        let childCount = yxmlelem_child_len(fragment, txn)
        guard childCount > 0 else { return nil }

        var parts: [String] = []
        parts.reserveCapacity(Int(min(childCount, 64)))
        var budget = maxNodes

        for index in 0..<childCount {
            guard budget > 0 else { break }
            guard let output = yxmlelem_get(fragment, txn, index) else { continue }
            if let piece = renderNode(output, txn: txn, depth: 0, budget: &budget), !piece.isEmpty {
                parts.append(piece)
            }
        }

        let xml = parts.joined()
        return xml.isEmpty ? nil : xml
    }

    #if DEBUG
    /// Logs element/text shape from yrs walk (differs from `Y.XmlFragment.toString()` on web).
    static func debugFragmentStructure(txn: OpaquePointer) -> String {
        guard let fragment = ytype_get(txn, "description") else { return "no-fragment" }
        var parts: [String] = []
        var budget = 80
        let childCount = yxmlelem_child_len(fragment, txn)
        for index in 0..<childCount where budget > 0 {
            guard let output = yxmlelem_get(fragment, txn, index) else { continue }
            debugDescribeNode(output, txn: txn, depth: 0, parts: &parts, budget: &budget)
        }
        return parts.joined(separator: ",")
    }

    private static func debugDescribeNode(
        _ output: UnsafePointer<YOutput>,
        txn: OpaquePointer,
        depth: Int,
        parts: inout [String],
        budget: inout Int
    ) {
        guard budget > 0, depth < 6 else { return }
        budget -= 1
        switch output.pointee.tag {
        case YrsValue.Y_XML_ELEM:
            guard let branch = youtput_read_yxmlelem(UnsafeMutablePointer(mutating: output)) else { return }
            let tag = elementTag(branch)
            parts.append("e:\(tag.isEmpty ? "?" : tag)")
            let count = yxmlelem_child_len(branch, txn)
            for index in 0..<count where budget > 0 {
                guard let child = yxmlelem_get(branch, txn, index) else { continue }
                debugDescribeNode(child, txn: txn, depth: depth + 1, parts: &parts, budget: &budget)
            }
        case YrsValue.Y_XML_TEXT:
            var chunkCount: UInt32 = 0
            guard let branch = youtput_read_yxmltext(UnsafeMutablePointer(mutating: output)) else { return }
            if let chunks = ytext_chunks(branch, txn, &chunkCount), chunkCount > 0 {
                defer { ychunks_destroy(chunks, chunkCount) }
                for index in 0..<chunkCount where budget > 0 {
                    let chunk = chunks[Int(index)]
                    var fmtKeys: [String] = []
                    if let fmt = chunk.fmt, chunk.fmt_len > 0 {
                        for fmtIndex in 0..<Int(chunk.fmt_len) {
                            if let key = fmt[fmtIndex].key {
                                fmtKeys.append(String(cString: key))
                            }
                        }
                    }
                    let href = linkHref(fromFormatEntries: chunk.fmt, count: chunk.fmt_len, txn: txn)
                    let label = href.map { "link(\($0.prefix(30)))" }
                        ?? (fmtKeys.isEmpty ? "plain" : fmtKeys.joined(separator: "+"))
                    if let text = stringFromOutput(chunk.data), text.contains("http") {
                        parts.append("t[\(label)]:\(text.prefix(40))")
                    } else {
                        parts.append("t:\(label)")
                    }
                    budget -= 1
                }
            } else {
                let hasLink = linkHrefFromTextAttributeKeys(branch: branch, txn: txn) != nil
                parts.append(hasLink ? "t:linkAttr" : "t:text")
            }
        default:
            parts.append("?")
        }
    }
    #endif

    /// Converts ProseMirror XML to HTML outside the Yrs transaction.
    static func html(fromSerializedXML xml: String, ingredients: [IngredientData]) -> String? {
        guard !xml.isEmpty else { return nil }
        let converted = convertProsemirrorXML(xml, ingredients: ingredients)
        let trimmed = converted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Bounded FFI walk (no yxmlelem_string)

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
        case "paragraph":
            // Always emit <p> even when empty so empty list items render.
            return "<p>\(inner)</p>"
        case "hardBreak":
            return "<br/>"
        case "horizontalRule":
            return "<hr/>"
        case "bulletList":
            return wrap("ul", inner)
        case "orderedList":
            return wrap("ol", inner)
        case "listItem":
            // Always emit <li> even when its paragraph is empty.
            return "<li>\(inner)</li>"
        case "blockquote":
            return wrap("blockquote", inner)
        case "codeBlock":
            return wrap("pre", inner)
        case "bold":
            return wrap("strong", inner)
        case "italic":
            return wrap("em", inner)
        case "strike":
            return wrap("s", inner)
        case "highlight":
            return wrap("mark", inner)
        case "code":
            return wrap("code", inner)
        case "heading":
            let level = elementAttribute(branch: branch, txn: txn, name: "level").flatMap(Int.init) ?? 1
            let clamped = min(6, max(1, level))
            return wrap("h\(clamped)", inner)
        case "link", "a":
            let href = elementAttribute(branch: branch, txn: txn, name: "href") ?? ""
            guard !href.isEmpty else { return inner }
            return #"<a href="\#(escapeAttr(href))" target="_blank" rel="noopener noreferrer">\#(inner)</a>"#
        case "timer":
            let attrs = timerDataAttributes(branch: branch, txn: txn)
            let label = inner.isEmpty ? timerFallbackLabel(from: branch, txn: txn) : inner
            return #"<span class="timer-reference"\#(attrs)>\#(escapeHTML(label))</span>"#
        case "ingredient":
            let id = elementAttribute(branch: branch, txn: txn, name: "data-ingredient-id") ?? ""
            let ratio = elementAttribute(branch: branch, txn: txn, name: "data-ratio") ?? "1"
            let amount = elementAttribute(branch: branch, txn: txn, name: "data-original-amount")
                ?? inner
            return #"<span class="ingredient-reference" data-ingredient-id="\#(escapeAttr(id))" data-ratio="\#(escapeAttr(ratio))">\#(escapeHTML(amount))</span>"#
        default:
            return inner
        }
    }

    /// Tiptap/y-prosemirror stores link (and other marks) on `Y.XmlText` delta chunks, not as `href` on the node.
    private static func renderXmlText(_ branch: UnsafeMutablePointer<Branch>, txn: OpaquePointer) -> String? {
        var chunkCount: UInt32 = 0
        if let chunks = ytext_chunks(branch, txn, &chunkCount), chunkCount > 0 {
            defer { ychunks_destroy(chunks, chunkCount) }
            var parts: [String] = []
            parts.reserveCapacity(Int(chunkCount))
            for index in 0..<chunkCount {
                let chunk = chunks[Int(index)]
                guard let text = stringFromOutput(chunk.data), !text.isEmpty else { continue }
                let escaped = escapeHTML(text)
                let href = resolvedLinkHref(
                    text: text,
                    fmt: chunk.fmt,
                    fmtLen: chunk.fmt_len,
                    txn: txn
                )
                if let href, !href.isEmpty {
                    parts.append(#"<a href="\#(escapeAttr(href))" target="_blank" rel="noopener noreferrer">\#(escaped)</a>"#)
                } else {
                    parts.append(
                        wrapWithInlineMarks(
                            escaped,
                            fmt: chunk.fmt,
                            fmtLen: chunk.fmt_len
                        )
                    )
                }
            }
            let joined = parts.joined()
            if !joined.isEmpty { return joined }
        }

        guard let cStr = yxmltext_string(branch, txn) else { return nil }
        defer { ystring_destroy(cStr) }
        let text = escapeHTML(String(cString: cStr))
        if let href = linkHrefFromTextAttributeKeys(branch: branch, txn: txn), !href.isEmpty {
            return #"<a href="\#(escapeAttr(href))" target="_blank" rel="noopener noreferrer">\#(text)</a>"#
        }
        if let href = textAttribute(branch: branch, txn: txn, name: "href"), !href.isEmpty {
            return #"<a href="\#(escapeAttr(href))" target="_blank" rel="noopener noreferrer">\#(text)</a>"#
        }
        return text
    }

    private static func stringFromOutput(_ output: YOutput) -> String? {
        withUnsafePointer(to: output) { ptr in
            guard let cStr = youtput_read_string(ptr) else { return nil }
            return String(cString: cStr)
        }
    }

    private static func resolvedLinkHref(
        text: String,
        fmt: UnsafePointer<YMapEntry>?,
        fmtLen: UInt32,
        txn: OpaquePointer
    ) -> String? {
        if let href = linkHref(fromFormatEntries: fmt, count: fmtLen, txn: txn), !href.isEmpty {
            return href
        }
        guard formattingHasLinkMark(fmt: fmt, count: fmtLen) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return nil
    }

    private static func formattingHasLinkMark(
        fmt: UnsafePointer<YMapEntry>?,
        count: UInt32
    ) -> Bool {
        formattingHasMark(fmt: fmt, count: count, mark: "link")
    }

    private static func formattingHasMark(
        fmt: UnsafePointer<YMapEntry>?,
        count: UInt32,
        mark: String
    ) -> Bool {
        guard let fmt, count > 0 else { return false }
        for index in 0..<Int(count) {
            guard let namePtr = fmt[index].key else { continue }
            let name = String(cString: namePtr)
            if name == mark || name.hasPrefix("\(mark)--") { return true }
        }
        return false
    }

    /// ProseMirror/Tiptap inline marks on `Y.XmlText` delta chunks (parity with description-editor-bridge.js).
    private static func wrapWithInlineMarks(
        _ escaped: String,
        fmt: UnsafePointer<YMapEntry>?,
        fmtLen: UInt32
    ) -> String {
        guard !escaped.isEmpty else { return escaped }
        var out = escaped
        if formattingHasMark(fmt: fmt, count: fmtLen, mark: "bold") {
            out = "<strong>\(out)</strong>"
        }
        if formattingHasMark(fmt: fmt, count: fmtLen, mark: "italic") {
            out = "<em>\(out)</em>"
        }
        if formattingHasMark(fmt: fmt, count: fmtLen, mark: "strike") {
            out = "<s>\(out)</s>"
        }
        if formattingHasMark(fmt: fmt, count: fmtLen, mark: "code") {
            out = "<code>\(out)</code>"
        }
        if formattingHasMark(fmt: fmt, count: fmtLen, mark: "highlight") {
            out = "<mark>\(out)</mark>"
        }
        return out
    }

    private static func linkHref(
        fromFormatEntries fmt: UnsafePointer<YMapEntry>?,
        count: UInt32,
        txn: OpaquePointer
    ) -> String? {
        guard let fmt, count > 0 else { return nil }
        for index in 0..<Int(count) {
            let entry = fmt[index]
            guard let namePtr = entry.key else { continue }
            let name = String(cString: namePtr)
            guard name == "link" || name.hasPrefix("link--") else { continue }
            if let href = hrefFromMarkOutput(entry.value, txn: txn), !href.isEmpty {
                return href
            }
        }
        return nil
    }

    private static func linkHrefFromTextAttributeKeys(
        branch: UnsafeMutablePointer<Branch>,
        txn: OpaquePointer
    ) -> String? {
        guard let iter = yxmltext_attr_iter(branch, txn) else { return nil }
        defer { yxmlattr_iter_destroy(iter) }
        while let attr = yxmlattr_iter_next(iter) {
            defer { yxmlattr_destroy(attr) }
            guard let namePtr = attr.pointee.name else { continue }
            let name = String(cString: namePtr)
            guard name == "link" || name.hasPrefix("link--") else { continue }
            if let href = hrefFromMarkOutput(attr.pointee.value, txn: txn), !href.isEmpty {
                return href
            }
        }
        return nil
    }

    private static func hrefFromMarkOutput(_ output: UnsafePointer<YOutput>?, txn: OpaquePointer) -> String? {
        guard let output else { return nil }
        switch output.pointee.tag {
        case YrsValue.Y_JSON_MAP, YrsValue.Y_MAP:
            guard let map = youtput_read_ymap(UnsafeMutablePointer(mutating: output)) else {
                return hrefFromEmbeddedJsonMap(output)
            }
            return YrsMap(branch: map).string(key: "href", txn: txn)
        case YrsValue.Y_JSON_STR:
            guard let cStr = youtput_read_string(UnsafeMutablePointer(mutating: output)) else { return nil }
            let raw = String(cString: cStr)
            return parseAttribute(raw, name: "href") ?? (raw.hasPrefix("http") ? raw : nil)
        default:
            return nil
        }
    }

    /// Read-only scan of `youtput_read_json_map` — do not call `ymap_entry_destroy` (freed with parent `YOutput`).
    private static func hrefFromEmbeddedJsonMap(_ output: UnsafePointer<YOutput>) -> String? {
        guard output.pointee.tag == YrsValue.Y_JSON_MAP else { return nil }
        guard let entries = youtput_read_json_map(UnsafeMutablePointer(mutating: output)) else { return nil }
        let count = Int(output.pointee.len)
        guard count > 0 else { return nil }
        for index in 0..<count {
            let entry = entries[index]
            guard let keyPtr = entry.key else { continue }
            guard String(cString: keyPtr) == "href" else { continue }
            guard let value = entry.value else { continue }
            if value.pointee.tag == YrsValue.Y_JSON_STR,
               let cStr = youtput_read_string(UnsafeMutablePointer(mutating: value)) {
                return String(cString: cStr)
            }
        }
        return nil
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

    private static func timerDataAttributes(branch: UnsafeMutablePointer<Branch>, txn: OpaquePointer) -> String {
        let keys = ["data-timer-id", "data-duration", "data-type", "data-name", "data-value"]
        var parts: [String] = []
        for key in keys {
            if let value = elementAttribute(branch: branch, txn: txn, name: key), !value.isEmpty {
                parts.append(#"\#(key)="\#(escapeAttr(value))""#)
            }
        }
        return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

    private static func textAttribute(
        branch: UnsafeMutablePointer<Branch>,
        txn: OpaquePointer,
        name: String
    ) -> String? {
        guard let output = yxmltext_get_attr(branch, txn, name) else { return nil }
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

    // MARK: - XML → HTML (Swift-only)

    private static func convertProsemirrorXML(_ xml: String, ingredients: [IngredientData]) -> String {
        var output = xml
        output = replaceTag(output, from: "paragraph", to: "p")
        output = replaceTag(output, from: "bulletList", to: "ul")
        output = replaceTag(output, from: "orderedList", to: "ol")
        output = replaceTag(output, from: "listItem", to: "li")
        output = replaceTag(output, from: "blockquote", to: "blockquote")
        output = replaceTag(output, from: "codeBlock", to: "pre")
        output = replaceTag(output, from: "hardBreak", to: "br", selfClosing: true)
        output = replaceTag(output, from: "horizontalRule", to: "hr", selfClosing: true)
        output = replaceHeadingTags(output)
        output = replaceTag(output, from: "bold", to: "strong")
        output = replaceTag(output, from: "italic", to: "em")
        output = replaceTag(output, from: "strike", to: "s")
        output = replaceTag(output, from: "highlight", to: "mark")
        output = replaceTag(output, from: "code", to: "code")
        output = replaceLinkNodes(output)
        output = replaceIngredientNodes(output, ingredients: ingredients)
        output = replaceTimerNodes(output)
        output = replaceTag(output, from: "doc", to: "div")
        output = replaceTag(output, from: "undefined", to: "div")
        return stripUnknownTags(output)
    }

    private static func replaceTag(
        _ xml: String,
        from source: String,
        to target: String,
        selfClosing: Bool = false
    ) -> String {
        var result = xml
        if selfClosing {
            result = result.replacingOccurrences(
                of: "<\(source)([^>]*)/>",
                with: "<\(target)$1/>",
                options: .regularExpression
            )
        }
        result = result.replacingOccurrences(
            of: "<\(source)([^>]*)>",
            with: "<\(target)$1>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "</\(source)>", with: "</\(target)>")
        return result
    }

    private static func replaceHeadingTags(_ xml: String) -> String {
        let pattern = #"<heading([^>]*)>(.*?)</heading>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return xml
        }
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return xml }

        var result = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let attrs = match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1))
                : ""
            let inner = match.range(at: 2).location != NSNotFound
                ? ns.substring(with: match.range(at: 2))
                : ""
            let level = parseAttribute(attrs, name: "level").flatMap(Int.init) ?? 1
            let clamped = min(6, max(1, level))
            result += "<h\(clamped)>\(inner)</h\(clamped)>"
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func replaceLinkNodes(_ xml: String) -> String {
        let pattern = #"<link([^>]*)>(.*?)</link>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return xml
        }
        let ns = xml as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let attrs = match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1))
                : ""
            let inner = match.range(at: 2).location != NSNotFound
                ? ns.substring(with: match.range(at: 2))
                : ""
            let href = parseAttribute(attrs, name: "href") ?? ""
            result += #"<a href="\#(escapeAttr(href))" target="_blank" rel="noopener noreferrer">\#(inner)</a>"#
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func replaceIngredientNodes(_ xml: String, ingredients: [IngredientData]) -> String {
        let pattern = #"<ingredient([^>]*)(?:/>|></ingredient>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return xml }
        let ns = xml as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let attrs = match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1))
                : ""
            result += ingredientLabel(attrs: attrs, ingredients: ingredients)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func replaceTimerNodes(_ xml: String) -> String {
        let pattern = #"<timer([^>]*)(?:>(.*?)</timer>|/>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return xml
        }
        let ns = xml as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let attrs = match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1))
                : ""
            let inner = match.range(at: 2).location != NSNotFound
                ? ns.substring(with: match.range(at: 2))
                : ""
            if !inner.isEmpty {
                result += inner
            } else if let value = parseAttribute(attrs, name: "data-value")
                ?? parseAttribute(attrs, name: "data-duration") {
                let unit = parseAttribute(attrs, name: "data-type") ?? "minutes"
                result += escapeHTML("\(value) \(unit)")
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func ingredientLabel(attrs: String, ingredients: [IngredientData]) -> String {
        guard let ingredientId = parseAttribute(attrs, name: "data-ingredient-id"),
              !ingredientId.isEmpty,
              let ingredient = ingredients.first(where: { $0.id == ingredientId })
        else { return "" }

        let ratio = Double(parseAttribute(attrs, name: "data-ratio") ?? "") ?? 1
        let baseStr = ingredient.originalAmount.isEmpty ? ingredient.amount : ingredient.originalAmount
        let amountText: String
        if let numeric = Double(baseStr.replacingOccurrences(of: ",", with: ".")) {
            amountText = formatAmount(numeric * ratio)
        } else if !baseStr.isEmpty {
            amountText = baseStr
        } else {
            amountText = ingredient.amount
        }
        let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var label = amountText
        if !unit.isEmpty { label += " \(unit)" }
        if !name.isEmpty {
            label = label.isEmpty ? name : "\(label) \(name)"
        }
        return label.isEmpty ? "" : escapeHTML(label)
    }

    private static func stripUnknownTags(_ xml: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "</?([a-zA-Z][a-zA-Z0-9]*)[^>]*>") else {
            return xml
        }
        let allowed = Set([
            "p", "ul", "ol", "li", "blockquote", "pre", "br", "hr",
            "h1", "h2", "h3", "h4", "h5", "h6",
            "strong", "em", "s", "mark", "code", "a", "div", "span",
        ])
        let ns = xml as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let tag = match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1)).lowercased()
                : ""
            if allowed.contains(tag) {
                result += ns.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func elementTag(_ branch: UnsafeMutablePointer<Branch>) -> String {
        guard let cStr = yxmlelem_tag(branch) else { return "" }
        return String(cString: cStr)
    }

    private static func escapeAttr(_ value: String) -> String {
        escapeHTML(value)
    }

    private static func parseAttribute(_ attrs: String, name: String) -> String? {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attrs, range: NSRange(location: 0, length: (attrs as NSString).length)),
              match.numberOfRanges > 1,
              match.range(at: 1).location != NSNotFound
        else { return nil }
        return (attrs as NSString).substring(with: match.range(at: 1))
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func wrap(_ tag: String, _ inner: String) -> String {
        guard !inner.isEmpty else { return "" }
        return "<\(tag)>\(inner)</\(tag)>"
    }

    private static func formatAmount(_ value: Double) -> String {
        // TP14 [review #14]: guard NaN/Inf and out-of-Int64 range before cast.
        guard value.isFinite else { return "" }
        if value.rounded(.towardZero) == value, let intValue = Int(exactlySafe: value.rounded()) {
            return String(intValue)
        }
        var text = String(format: "%.2f", value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}