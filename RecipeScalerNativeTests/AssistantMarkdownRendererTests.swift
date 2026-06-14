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

    func testAgentationStyleExample() {
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
