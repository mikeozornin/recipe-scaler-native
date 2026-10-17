import UIKit
import XCTest
@testable import RecipeScalerNative

final class AssistantMarkdownRendererTests: XCTestCase {
    func testParsesHeaderBlock() {
        let blocks = AssistantMarkdownRenderer.blocks(from: "## Кофе во френч-прессе")
        XCTAssertEqual(blocks.count, 1)
        guard case .header(let level, let text) = blocks[0] else {
            return XCTFail("Expected header block")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(text, "Кофе во френч-прессе")
    }

    func testParsesOrderedListBlock() {
        let blocks = AssistantMarkdownRenderer.blocks(from: "1. Прогрейте колбу.\n2. Засыпьте кофе.")
        XCTAssertEqual(blocks.count, 1)
        guard case .orderedList(let items) = blocks[0] else {
            return XCTFail("Expected ordered list block")
        }
        XCTAssertEqual(items, ["Прогрейте колбу.", "Засыпьте кофе."])
    }

    func testParsesUnorderedListWithDoubleSpaceAfterMarker() {
        let markdown = """
        *  **Кофе:** 20 г (помол крупный, как морская соль).
        *  **Вода:** 300 г (температура 92–95°C).
        *  **Время заваривания:** 4 минуты.
        """
        let blocks = AssistantMarkdownRenderer.blocks(from: markdown)
        XCTAssertEqual(blocks.count, 1)
        guard case .unorderedList(let items) = blocks[0] else {
            return XCTFail("Expected unordered list block, got \(blocks.map(\.debugTypeName))")
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].hasPrefix("**Кофе:**"))
        XCTAssertFalse(items[0].hasPrefix("* "))
    }

    func testStrongEmphasisUsesBodyMediumAtSameSize() {
        let attributed = AssistantMarkdownRenderer.inlineAttributedString(from: "**Location:** path")
        let plain = String(attributed.characters)
        guard let range = plain.range(of: "Location:") else {
            return XCTFail("Missing emphasized text")
        }
        let index = AttributedString.Index(range.lowerBound, within: attributed)
        guard let index else {
            return XCTFail("Missing attributed index")
        }
        let strongRun = attributed.runs.first { run in
            run.range.contains(index)
        }
        guard let strongFont = strongRun?.uiKit.font else {
            return XCTFail("Missing strong font")
        }
        guard let trailingRange = plain.range(of: " path") else {
            return XCTFail("Missing regular text")
        }
        let regularIndex = AttributedString.Index(trailingRange.lowerBound, within: attributed)
        guard let regularIndex else {
            return XCTFail("Missing regular attributed index")
        }
        let regularRun = attributed.runs.first { run in
            run.range.contains(regularIndex)
        }
        guard let regularFont = regularRun?.uiKit.font else {
            return XCTFail("Missing regular font")
        }
        XCTAssertEqual(strongFont.fontName, AppTypography.sansMediumBodyUIFont.fontName)
        XCTAssertEqual(strongFont.pointSize, regularFont.pointSize)
        XCTAssertEqual(regularFont.fontName, AppTypography.bodyUIFont.fontName)
    }

    func testSafeLinkIsPreserved() {
        let attributed = AssistantMarkdownRenderer.inlineAttributedString(from: "[safe](https://example.com)")
        XCTAssertTrue(AssistantMarkdownRenderer.hasLink(in: attributed, hrefContains: "example.com"))
    }

    func testUnsafeJavascriptLinkIsStripped() {
        let attributed = AssistantMarkdownRenderer.inlineAttributedString(from: "[x](javascript:alert(1))")
        XCTAssertFalse(AssistantMarkdownRenderer.hasLink(in: attributed, hrefContains: "javascript"))
    }

    func testSingleNewlineBecomesHardBreak() {
        let preprocessed = AssistantMarkdownRenderer.preprocessForRemarkBreaks("line one\nline two")
        XCTAssertEqual(preprocessed, "line one  \nline two")
    }

    func testDoubleNewlinePreservesParagraphBreak() {
        let preprocessed = AssistantMarkdownRenderer.preprocessForRemarkBreaks("para one\n\npara two")
        XCTAssertEqual(preprocessed, "para one\n\npara two")
    }

    func testParagraphPreservesInlineLineBreak() {
        let attributed = AssistantMarkdownRenderer.inlineAttributedString(
            from: AssistantMarkdownRenderer.preprocessForRemarkBreaks("**Кофе:** 20 г\n**Вода:** 300 г")
        )
        XCTAssertEqual(String(attributed.characters).filter { $0 == "\n" }.count, 1)
    }

    func testSplitsMultipleParagraphBlocks() {
        let blocks = AssistantMarkdownRenderer.blocks(from: "## Title\n\nFirst paragraph.\n\nSecond paragraph.")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.map(\.debugTypeName), ["h2", "p", "p"])
    }

    func testHeaderUsesDisplayBoldFace() {
        let attributed = AssistantMarkdownRenderer.headerAttributedString(from: "Классика:", level: 3)
        guard let font = attributed.runs.first?.uiKit.font else {
            return XCTFail("Missing header font")
        }
        XCTAssertEqual(font.fontName, AppTypography.uiFont(AppFonts.display, size: AppTypography.bodySize).fontName)
        XCTAssertEqual(font.pointSize, AppTypography.bodySize)
    }

    func testSplitsHeaderAndListInSameBlock() {
        let markdown = """
        ### Классика:
        * **Укроп:** свежий
        * **Цедра цитрусовых:** лимон
        """
        let blocks = AssistantMarkdownRenderer.blocks(from: markdown)
        XCTAssertEqual(blocks.map(\.debugTypeName), ["h3", "ul(2)"])
        guard case .header(let level, let text) = blocks[0] else {
            return XCTFail("Expected header")
        }
        XCTAssertEqual(level, 3)
        XCTAssertEqual(text, "Классика:")
        guard case .unorderedList(let items) = blocks[1] else {
            return XCTFail("Expected unordered list")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].hasPrefix("**Укроп:**"))
    }

    func testSectionHeadingAndLocationBoldExample() {
        let markdown = """
        ### 1. UIHostingController<ModifiedContent<AnyView, RootModifier>>
        **Location:** NavigationStackHostingController<AnyView> > "Инструкции"
        """
        let blocks = AssistantMarkdownRenderer.blocks(from: markdown)
        XCTAssertGreaterThanOrEqual(blocks.count, 2)
        let attributed = AssistantMarkdownRenderer.inlineAttributedString(from: "**Location:** path")
        XCTAssertTrue(AssistantMarkdownRenderer.hasStronglyEmphasizedRun(in: attributed, containing: "Location:"))
    }
}

// MARK: - Perf refactor parity (shared styles and fonts, block and render caches)

extension AssistantMarkdownRendererTests {
    func testBlocksMatchLegacyParserForCorpusAndFuzz() {
        for content in Self.parityCorpus + Self.fuzzCorpus() {
            XCTAssertEqual(
                AssistantMarkdownRenderer.blocks(from: content),
                LegacyAssistantMarkdown.blocks(from: content),
                "Blocks differ for \(content.debugDescription)"
            )
        }
    }

    func testRenderedTextMatchesLegacyRendererAndCache() {
        let storage = MarkdownCacheStorage()
        for content in Self.parityCorpus + Self.fuzzCorpus() {
            let blocks = storage.blocks(for: content, isStreaming: false)
            XCTAssertEqual(blocks, LegacyAssistantMarkdown.blocks(from: content))
            for block in blocks {
                // Second call is served from the cache and must be identical too.
                for _ in 0 ..< 2 {
                    XCTAssertEqual(
                        Self.render(block, storage: storage, storesResult: true),
                        LegacyAssistantMarkdown.render(block),
                        "Rendering differs for \(block)"
                    )
                }
            }
        }
    }

    func testStreamingChunksRenderSameAsWholeMessage() {
        var generator = SeededGenerator(seed: 0x5EED)
        for whole in Self.parityCorpus where !whole.isEmpty {
            let storage = MarkdownCacheStorage()
            var streamed = ""
            var remaining = Substring(whole)
            while !remaining.isEmpty {
                let chunkLength = Int(generator.next() % 7) + 1
                streamed += remaining.prefix(chunkLength)
                remaining = remaining.dropFirst(chunkLength)

                let blocks = storage.blocks(for: streamed, isStreaming: true)
                XCTAssertEqual(blocks, LegacyAssistantMarkdown.blocks(from: streamed))
                XCTAssertEqual(storage.blocks(for: streamed, isStreaming: true), blocks)
                for (index, block) in blocks.enumerated() {
                    XCTAssertEqual(
                        Self.render(block, storage: storage, storesResult: index < blocks.count - 1),
                        LegacyAssistantMarkdown.render(block)
                    )
                }
                if streamed != whole {
                    XCTAssertFalse(storage.hasCachedBlocks(for: streamed), "Streaming prefix leaked into cache")
                }
            }

            XCTAssertEqual(streamed, whole)
            let finalBlocks = storage.blocks(for: whole, isStreaming: false)
            XCTAssertEqual(finalBlocks, LegacyAssistantMarkdown.blocks(from: whole))
            XCTAssertTrue(storage.hasCachedBlocks(for: whole))
            XCTAssertEqual(
                finalBlocks.map { Self.render($0, storage: storage, storesResult: true) },
                finalBlocks.map(LegacyAssistantMarkdown.render)
            )
        }
    }

    func testStreamingTailBlockIsNotStored() {
        let storage = MarkdownCacheStorage()
        _ = storage.inlineAttributedString(for: "Сними с ог", storesResult: false)
        XCTAssertFalse(storage.hasCachedInlineText("Сними с ог"))
        _ = storage.inlineAttributedString(for: "Сними с огня", storesResult: true)
        XCTAssertTrue(storage.hasCachedInlineText("Сними с огня"))
    }

    // MARK: Helpers

    private static func render(
        _ block: AssistantMarkdownBlock,
        storage: MarkdownCacheStorage,
        storesResult: Bool
    ) -> AttributedString {
        switch block {
        case .header(let level, let text):
            return storage.headerAttributedString(for: text, level: level, storesResult: storesResult)
        case .paragraph(let text):
            return storage.inlineAttributedString(for: text, storesResult: storesResult)
        case .orderedList(let items), .unorderedList(let items):
            return items.reduce(into: AttributedString()) { result, item in
                result += storage.inlineAttributedString(for: item, storesResult: storesResult)
                result += AttributedString("\u{1}")
            }
        }
    }

    static let parityCorpus: [String] = [
        "",
        "   ",
        "\n\n\n",
        "Просто текст.",
        "## Кофе во френч-прессе",
        "# H1 title",
        "###### six",
        "####### seven is not a header",
        "#no space",
        "# ",
        "#",
        "### 1. UIHostingController<ModifiedContent<AnyView, RootModifier>>\n**Location:** path > \"Инструкции\"",
        "1. Прогрейте колбу.\n2. Засыпьте кофе.\n10. Десятый.",
        "1.no space\n2. ok",
        "*  **Кофе:** 20 г (помол крупный).\n*  **Вода:** 300 г (92–95°C).\n*  **Время:** 4 минуты.",
        "- a\n+ b\n* c",
        "-\n- \n-x",
        "Ингредиенты:\n- мука\n- сахар",
        "Шаги:\n1. Смешать\n2. Выпекать",
        "### Классика:\n* **Укроп:** свежий\n* **Цедра:** лимон\n\nДальше абзац.",
        "Line one\nline two\n\n\nline three",
        "CRLF line\r\nnext\r\n\r\n- item\r\n- item two\r\n",
        "1. \u{301}combining after marker\n2. ok",
        "- \u{301}x\n- y",
        "Château **gras** `code` _it_ *em* ~~del~~",
        "[safe](https://example.com) and [bad](javascript:alert(1)) and [d](data:text/html,x)",
        "Emoji 😀 and family 👨‍👩‍👧 in **bold 🍝**",
        "Object \u{FFFC} replacement\n\n\u{FFFC}\u{FFFC}",
        "\t- tabbed\n\t- list",
        "  ## indented header  ",
        "**unclosed bold\n\n`unclosed code",
        String(repeating: "Длинный абзац с **жирным** и `кодом`. ", count: 40)
            + "\n\n- " + Array(repeating: "пункт", count: 30).joined(separator: "\n- "),
    ]

    static func fuzzCorpus(count: Int = 400) -> [String] {
        let pieces = [
            "1.", "2.", "10.", " ", "  ", "\n", "\n\n", "\r\n", "\t", "-", "*", "+", "#", "##", "**", "`",
            "_", "a", "Б", "word", "\u{301}", "😀", "👨‍👩‍👧", "\u{FFFC}", "[x](https://e.com)",
            "[y](javascript:z)", "é", "~",
        ]
        var generator = SeededGenerator(seed: 42)
        return (0 ..< count).map { _ in
            let length = Int(generator.next() % 24)
            return (0 ..< length).map { _ in pieces[Int(generator.next() % UInt64(pieces.count))] }.joined()
        }
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Verbatim copy of the renderer before the perf change (per-call paragraph styles
/// and font lookups, no caches), used as the parity reference.
private enum LegacyAssistantMarkdown {
    static func blocks(from content: String) -> [AssistantMarkdownBlock] {
        let preprocessed = AssistantMarkdownRenderer.preprocessForRemarkBreaks(content)
        return preprocessed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap(parseRawBlock)
    }

    static func render(_ block: AssistantMarkdownBlock) -> AttributedString {
        switch block {
        case .header(let level, let text):
            return header(text, level: level)
        case .paragraph(let text):
            return inline(text)
        case .orderedList(let items), .unorderedList(let items):
            return items.reduce(into: AttributedString()) { result, item in
                result += inline(item)
                result += AttributedString("\u{1}")
            }
        }
    }

    static func inline(_ content: String) -> AttributedString {
        var attributed: AttributedString
        do {
            attributed = try AttributedString(
                markdown: content,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            attributed = AttributedString(content)
        }
        let bodyStyle = paragraphStyle(spacing: 0)
        for run in attributed.runs {
            var container = AttributeContainer()
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                container.font = font(AppFonts.mono, size: AppTypography.bodySize * 0.875)
            } else if intent.contains(.stronglyEmphasized) {
                container.font = font(AppFonts.sansMedium, size: AppTypography.bodySize)
            } else {
                container.font = font(AppFonts.sans, size: AppTypography.bodySize)
            }
            container.paragraphStyle = bodyStyle
            attributed[run.range].mergeAttributes(container)
        }
        for run in attributed.runs where run.inlinePresentationIntent != nil {
            attributed[run.range].inlinePresentationIntent = nil
        }
        for run in attributed.runs {
            guard let url = run.link else {
                continue
            }
            if !AssistantMarkdownRenderer.isSafeHref(url.absoluteString) {
                attributed[run.range].link = nil
            }
        }
        return attributed
    }

    static func header(_ text: String, level: Int) -> AttributedString {
        var attributed = inline(text)
        let style = paragraphStyle(spacing: 4)
        let headerFont = font(
            AppFonts.display,
            size: level == 1 ? AppTypography.title2Size : AppTypography.bodySize
        )
        for run in attributed.runs {
            var container = AttributeContainer()
            container.font = headerFont
            container.paragraphStyle = style
            attributed[run.range].mergeAttributes(container)
            attributed[run.range].inlinePresentationIntent = nil
            attributed[run.range].presentationIntent = nil
        }
        return attributed
    }

    private static func paragraphStyle(spacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = AppTypography.bodyLineSpacing
        style.paragraphSpacing = spacing
        return style
    }

    /// Uncached copy of `AppTypography.uiFont` resolution.
    private static func font(_ name: String, size: CGFloat) -> UIFont {
        func resolve(_ face: String) -> UIFont? {
            UIFont(name: face, size: size)
                ?? AppFonts.postScriptName(for: face).flatMap { UIFont(name: $0, size: size) }
        }
        return resolve(name) ?? resolve(AppFonts.sans) ?? .systemFont(ofSize: size)
    }

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
        if lines.count > 1, !isUnorderedListLine(lines[0]), lines.dropFirst().allSatisfy(isUnorderedListLine) {
            return [
                .paragraph(text: lines[0]),
                .unorderedList(items: lines.dropFirst().map(stripUnorderedListMarker)),
            ]
        }
        if lines.count > 1, !isOrderedListLine(lines[0]), lines.dropFirst().allSatisfy(isOrderedListLine) {
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
}
