//
//  AssistantMarkdownRenderer.swift
//  RecipeScalerNative
//
//  Markdown subset for assistant chat bubbles. Web parity: assistant-markdown.tsx.
//

import SwiftUI
import UIKit

enum AssistantMarkdownBlock: Equatable {
    case header(level: Int, text: String)
    case paragraph(text: String)
    case orderedList(items: [String])
    case unorderedList(items: [String])

    var debugTypeName: String {
        switch self {
        case .header(let level, _):
            return "h\(level)"
        case .paragraph:
            return "p"
        case .orderedList(let items):
            return "ol(\(items.count))"
        case .unorderedList(let items):
            return "ul(\(items.count))"
        }
    }
}

enum AssistantMarkdownRenderer {
    private static let paragraphBreakPlaceholder = "\u{FFFC}"

    private static let inlineMarkdownOptions = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )

    static func blocks(from content: String) -> [AssistantMarkdownBlock] {
        let preprocessed = preprocessForRemarkBreaks(content)
        let rawBlocks = preprocessed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let blocks = rawBlocks.flatMap(parseRawBlock)

        logRenderDiagnostics(content: content, blocks: blocks)
        return blocks
    }

    static func attributedString(from content: String) -> AttributedString {
        inlineAttributedString(from: content)
    }

    static func inlineAttributedString(from content: String) -> AttributedString {
        var attributed: AttributedString
        do {
            attributed = try AttributedString(markdown: content, options: inlineMarkdownOptions)
        } catch {
            attributed = AttributedString(content)
        }

        applyInlineStyles(to: &attributed)
        stripInlinePresentationIntents(in: &attributed)
        stripUnsafeLinks(in: &attributed)

        return attributed
    }

    static func headerAttributedString(from text: String, level: Int) -> AttributedString {
        var attributed = inlineAttributedString(from: text)
        let headerStyle = headerParagraphStyle()
        let headerFont = headerUIFont(level: level)

        for run in attributed.runs {
            var container = AttributeContainer()
            container.font = headerFont
            container.paragraphStyle = headerStyle
            attributed[run.range].mergeAttributes(container)
            attributed[run.range].inlinePresentationIntent = nil
            attributed[run.range].presentationIntent = nil
        }

        return attributed
    }

    static func preprocessForRemarkBreaks(_ content: String) -> String {
        let withPlaceholder = content.replacingOccurrences(
            of: "\n\n",
            with: paragraphBreakPlaceholder
        )
        let withHardBreaks = withPlaceholder.replacingOccurrences(of: "\n", with: "  \n")
        return withHardBreaks.replacingOccurrences(of: paragraphBreakPlaceholder, with: "\n\n")
    }

    static func isSafeHref(_ href: String) -> Bool {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.hasPrefix("javascript:")
            && !trimmed.hasPrefix("data:")
            && !trimmed.hasPrefix("vbscript:")
    }

    static func topSpacing(for block: AssistantMarkdownBlock, isFirst: Bool) -> CGFloat {
        if isFirst {
            return 0
        }
        switch block {
        case .header:
            return 12
        case .paragraph, .orderedList, .unorderedList:
            return 8
        }
    }

    // MARK: - Block parsing

    private static func parseRawBlock(_ raw: String) -> [AssistantMarkdownBlock] {
        if let header = parseHeader(raw), !raw.contains("\n") {
            return [.header(level: header.level, text: header.text)]
        }

        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return []
        }

        if let header = parseHeader(lines[0]) {
            var blocks: [AssistantMarkdownBlock] = [.header(level: header.level, text: header.text)]
            let tail = Array(lines.dropFirst())
            if !tail.isEmpty {
                blocks.append(contentsOf: parseLineGroup(tail))
            }
            return blocks
        }

        return parseLineGroup(lines)
    }

    private static func parseLineGroup(_ lines: [String]) -> [AssistantMarkdownBlock] {
        guard !lines.isEmpty else {
            return []
        }

        if lines.allSatisfy(isOrderedListLine) {
            return [.orderedList(items: lines.map(stripOrderedListMarker))]
        }

        if lines.allSatisfy(isUnorderedListLine) {
            return [.unorderedList(items: lines.map(stripUnorderedListMarker))]
        }

        if lines.count > 1,
           !isUnorderedListLine(lines[0]),
           lines.dropFirst().allSatisfy(isUnorderedListLine) {
            return [
                .paragraph(text: lines[0]),
                .unorderedList(items: lines.dropFirst().map(stripUnorderedListMarker)),
            ]
        }

        if lines.count > 1,
           !isOrderedListLine(lines[0]),
           lines.dropFirst().allSatisfy(isOrderedListLine) {
            return [
                .paragraph(text: lines[0]),
                .orderedList(items: lines.dropFirst().map(stripOrderedListMarker)),
            ]
        }

        return [.paragraph(text: lines.joined(separator: "\n"))]
    }

    private static func parseHeader(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), !trimmed.contains("\n") else {
            return nil
        }

        var level = 0
        for character in trimmed where character == "#" {
            level += 1
        }
        guard (1 ... 6).contains(level), trimmed.count > level else {
            return nil
        }

        let afterHashes = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard trimmed[afterHashes] == " " else {
            return nil
        }

        let text = String(trimmed[trimmed.index(after: afterHashes)...])
        guard !text.isEmpty else {
            return nil
        }
        return (level, text)
    }

    private static func isOrderedListLine(_ line: String) -> Bool {
        line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }

    private static func isUnorderedListLine(_ line: String) -> Bool {
        line.range(of: #"^[-*+]\s+\S"#, options: .regularExpression) != nil
    }

    private static func stripOrderedListMarker(_ line: String) -> String {
        guard let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else {
            return line
        }
        return String(line[range.upperBound...])
    }

    private static func stripUnorderedListMarker(_ line: String) -> String {
        guard let range = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) else {
            return line
        }
        return String(line[range.upperBound...])
    }

    // MARK: - Inline styling

    private static func applyInlineStyles(to attributed: inout AttributedString) {
        let bodyStyle = bodyParagraphStyle()

        for run in attributed.runs {
            var container = AttributeContainer()
            let inlineIntent = run.inlinePresentationIntent ?? []

            if inlineIntent.contains(.code) {
                container.font = monoUIFont()
            } else {
                container.font = bodyUIFont(strong: inlineIntent.contains(.stronglyEmphasized))
            }

            container.paragraphStyle = bodyStyle
            attributed[run.range].mergeAttributes(container)
        }
    }

    private static func stripInlinePresentationIntents(in attributed: inout AttributedString) {
        for run in attributed.runs where run.inlinePresentationIntent != nil {
            attributed[run.range].inlinePresentationIntent = nil
        }
    }

    private static func stripUnsafeLinks(in attributed: inout AttributedString) {
        for run in attributed.runs {
            guard let url = run.link else {
                continue
            }
            if !isSafeHref(url.absoluteString) {
                attributed[run.range].link = nil
            }
        }
    }

    private static func bodyUIFont(strong: Bool = false) -> UIFont {
        if strong {
            return AppTypography.sansMediumBodyUIFont
        }
        return AppTypography.bodyUIFont
    }

    private static func monoUIFont() -> UIFont {
        AppTypography.uiFont(AppFonts.mono, size: AppTypography.bodySize * 0.875)
    }

    private static func headerUIFont(level: Int) -> UIFont {
        if level == 1 {
            return AppTypography.uiFont(AppFonts.display, size: AppTypography.title2Size)
        }
        return AppTypography.uiFont(AppFonts.display, size: AppTypography.bodySize)
    }

    private static func headerParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = AppTypography.bodyLineSpacing
        style.paragraphSpacing = 4
        return style
    }

    private static func bodyParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = AppTypography.bodyLineSpacing
        style.paragraphSpacing = 0
        return style
    }

    // MARK: - Debug

    private static func logRenderDiagnostics(content: String, blocks: [AssistantMarkdownBlock]) {
        #if DEBUG
        guard AgentDebugLogging.isEnabled else {
            return
        }

        let sample = inlineAttributedString(from: blocks.firstInlineSample() ?? "")
        let sampleFontSize: String
        if let firstRun = sample.runs.first, let font = firstRun.uiKit.font {
            sampleFontSize = "\(font.pointSize)"
        } else {
            sampleFontSize = "unknown"
        }

        AgentSyncDebugLog.write(
            hypothesisId: "assistant-markdown",
            location: "AssistantMarkdownRenderer.logRenderDiagnostics",
            message: "assistant_markdown_rendered",
            data: [
                "topic": "assistant",
                "content_length": "\(content.count)",
                "newline_count": "\(content.filter { $0 == "\n" }.count)",
                "block_count": "\(blocks.count)",
                "block_types": blocks.map(\.debugTypeName).joined(separator: ","),
                "sample_font_pt": sampleFontSize,
                "body_font_pt": "\(AppTypography.bodySize)",
                "line_spacing_pt": "\(AppTypography.bodyLineSpacing)",
            ]
        )
        #endif
    }
}

private extension Array where Element == AssistantMarkdownBlock {
    func firstInlineSample() -> String? {
        for block in self {
            switch block {
            case .header(_, let text):
                return text
            case .paragraph(let text):
                return text
            case .orderedList(let items):
                return items.first
            case .unorderedList(let items):
                return items.first
            }
        }
        return nil
    }
}

#if DEBUG
extension AssistantMarkdownRenderer {
    static func headerLevel(in attributed: AttributedString, at index: AttributedString.Index) -> Int? {
        nil
    }

    static func hasStronglyEmphasizedRun(in attributed: AttributedString, containing text: String) -> Bool {
        let plain = String(attributed.characters)
        guard let range = plain.range(of: text) else {
            return false
        }
        let start = AttributedString.Index(range.lowerBound, within: attributed)
        guard let start else {
            return false
        }
        let mediumFontName = AppTypography.sansMediumBodyUIFont.fontName
        return attributed.runs.contains { run in
            run.range.contains(start) && run.uiKit.font?.fontName == mediumFontName
        }
    }

    static func hasLink(in attributed: AttributedString, hrefContains fragment: String) -> Bool {
        attributed.runs.contains { run in
            guard let url = run.link else {
                return false
            }
            return url.absoluteString.localizedCaseInsensitiveContains(fragment)
        }
    }

    static func hasListIntent(in attributed: AttributedString) -> Bool {
        false
    }
}
#endif
