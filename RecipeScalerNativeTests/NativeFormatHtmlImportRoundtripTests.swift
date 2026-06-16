import XCTest
import YrsC
@testable import RecipeScalerNative

/// Roundtrip tests for the v3 description XmlFragment when importing native format
/// (`.json` / `.zip`). Reproduces the bug where `applyNativeRecipe` used to wrap the
/// entire HTML string in a single paragraph and the reader saw raw markup.
///
/// Flow under test: HTML string → `RecipeDescriptionParser.parse` →
/// `RecipeDescriptionXmlFragmentWriter.apply` → `XmlFragmentToHTML.serializedFragment` →
/// asserts key elements (timers, ingredients, links, lists).
final class NativeFormatHtmlImportRoundtripTests: XCTestCase {

    // MARK: - Real-world recipe HTML (eda.ru khachapuri, as reported by the user)

    private let khachapuriHTML = """
    <p><a target="_blank" rel="noopener noreferrer" class="text-link text-blue-600 underline underline-offset-4 hover:text-red-600 transition-colors" href="https://eda.ru/recepty/vypechka-deserty/hachapuri-a-lya-po-adzharski-s-adygeyskim-syrom-i-mocarelloy-140380">https://eda.ru/recepty/vypechka-deserty/hachapuri-a-lya-po-adzharski-s-adygeyskim-syrom-i-mocarelloy-140380</a></p><ol><li><p>В <span data-ingredient-id="ingredient-0" data-original-amount="1" class="ingredient-reference edit-mode" contenteditable="false">1</span> стакан теплого молока всыпать дрожжи, сахар, <span data-ingredient-id="ingredient-3" data-original-amount="2" data-ratio="0.0033333333" class="ingredient-reference edit-mode" contenteditable="false">2</span> столовых ложки муки. Хорошо перемешать и оставить в теплом месте на <span data-timer-id="__TIMER_ID__" data-duration="1800" data-type="minutes" data-name="оставить опару" data-value="30" class="timer-reference" contenteditable="false">30 минут</span>. Следить, чтобы опара не сбежала.</p></li><li><p>В просеянную муку влить опару, мацони, добавить <span data-ingredient-id="ingredient-5" data-original-amount="3" data-ratio="0.025" class="ingredient-reference edit-mode" contenteditable="false">3</span> столовых ложки (<span data-ingredient-id="ingredient-5" data-original-amount="60" data-ratio="0.5" class="ingredient-reference edit-mode" contenteditable="false">60</span> г) мягкого сливочного масла, соль. Вымесить тесто руками или в комбайне на низкой скорости <span data-timer-id="__TIMER_ID__" data-duration="300" data-type="minutes" data-name="Вымесить тесто" data-value="5" class="timer-reference" contenteditable="false">5 минут</span>, затем на средней <span data-timer-id="__TIMER_ID__" data-duration="600" data-type="minutes" data-name="Вымесить тесто" data-value="10" class="timer-reference" contenteditable="false">10 минут</span>.</p></li></ol><p></p>
    """

    // MARK: - Parser: ingredient + timer attrs are preserved

    func testParserPreservesIngredientIdAndRatio() throws {
        let document = RecipeDescriptionParser.parse(khachapuriHTML)

        let ingredientRuns = document.blocks.flatMap { block -> [RecipeDescriptionInlineRun] in
            switch block {
            case .paragraph(_, let runs), .orderedStep(_, _, let runs),
                 .bullet(_, let runs), .heading(_, _, let runs):
                return runs
            }
        }.compactMap { run -> (id: String?, ratio: Double?)? in
            if case .ingredient(let id, let ratio, _, _) = run { return (id, ratio) }
            return nil
        }

        XCTAssertFalse(ingredientRuns.isEmpty, "Expected at least one ingredient run")
        XCTAssertTrue(ingredientRuns.contains { $0.id == "ingredient-0" })
        XCTAssertTrue(ingredientRuns.contains { $0.id == "ingredient-3" && abs(($0.ratio ?? 0) - 0.0033333333) < 1e-6 })
    }

    func testParserPreservesTimerAttributes() throws {
        let document = RecipeDescriptionParser.parse(khachapuriHTML)

        let timerRefs = document.blocks.flatMap { block -> [RecipeDescriptionTimerReference] in
            switch block {
            case .paragraph(_, let runs), .orderedStep(_, _, let runs),
                 .bullet(_, let runs), .heading(_, _, let runs):
                return runs.compactMap { run -> RecipeDescriptionTimerReference? in
                    if case .timer(let ref) = run { return ref }
                    return nil
                }
            }
        }

        XCTAssertTrue(timerRefs.contains { $0.durationSeconds == 1800 && $0.type == .minutes && $0.name == "оставить опару" })
        XCTAssertTrue(timerRefs.contains { $0.durationSeconds == 300 && $0.type == .minutes && $0.name == "Вымесить тесто" })
        XCTAssertTrue(timerRefs.contains { $0.durationSeconds == 600 })
    }

    // MARK: - Roundtrip: HTML → parse → Y.XmlFragment → HTML

    func testRoundtripPreservesOrderedListStructure() async throws {
        let html = try await roundtripHTML(from: khachapuriHTML)
        // The list wrapper survives as <ol><li><p>...</p></li></ol>
        XCTAssertTrue(html.contains("<ol>"), "Expected <ol> in \(html)")
        XCTAssertTrue(html.contains("<li><p>"), "Expected <li><p> in \(html)")
        // No raw angle brackets should leak into the output
        XCTAssertFalse(html.contains("&lt;p&gt;"), "Should not contain escaped <p> — got raw HTML as text in \(html)")
        XCTAssertFalse(html.contains("&lt;span"), "Should not contain escaped <span> in \(html)")
    }

    func testRoundtripPreservesLink() async throws {
        let html = try await roundtripHTML(from: khachapuriHTML)
        XCTAssertTrue(
            html.contains("href=\"https://eda.ru/recepty/vypechka-deserty/hachapuri-a-lya-po-adzharski-s-adygeyskim-syrom-i-mocarelloy-140380\""),
            "Expected eda.ru link href in \(html)"
        )
    }

    func testRoundtripPreservesTimerSpan() async throws {
        let html = try await roundtripHTML(from: khachapuriHTML)
        XCTAssertTrue(
            html.contains("class=\"timer-reference\""),
            "Expected timer-reference class in \(html)"
        )
        XCTAssertTrue(html.contains("data-duration=\"1800\""), "Expected data-duration=1800 in \(html)")
        XCTAssertTrue(html.contains("data-type=\"minutes\""), "Expected data-type=minutes in \(html)")
        XCTAssertTrue(html.contains("data-name=\"оставить опару\""), "Expected timer name in \(html)")
        XCTAssertTrue(html.contains("data-value=\"30\""), "Expected data-value=30 in \(html)")
        XCTAssertTrue(html.contains("30 минут"), "Expected timer display text in \(html)")
    }

    func testRoundtripPreservesIngredientSpan() async throws {
        let html = try await roundtripHTML(from: khachapuriHTML)
        XCTAssertTrue(
            html.contains("class=\"ingredient-reference\""),
            "Expected ingredient-reference class in \(html)"
        )
        XCTAssertTrue(html.contains("data-ingredient-id=\"ingredient-0\""), "Expected ingredient-0 id in \(html)")
        // XmlFragmentToHTML emits amount as inner text, not data-original-amount on the span.
        XCTAssertTrue(
            html.contains("data-ingredient-id=\"ingredient-0\" data-ratio=\"1\">1</span>"),
            "Expected ingredient-0 amount text in \(html)"
        )
        XCTAssertTrue(
            html.contains("data-ingredient-id=\"ingredient-3\""),
            "Expected ingredient-3 id with ratio preserved in \(html)"
        )
        XCTAssertTrue(html.contains("data-ratio=\"0.003333\""), "Expected ratio preserved in \(html)")
    }

    // MARK: - Edge cases

    func testRoundtripEmptyDocumentProducesNoContent() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()
        let document = RecipeDescriptionParser.parse("")
        try await doc.testApplyDescriptionDocument(document)
        let html = try await doc.testSerializedDescriptionHTML()
        XCTAssertNil(html, "Empty description should produce nil HTML, got: \(String(describing: html))")
    }

    func testRoundtripSimpleParagraph() async throws {
        let html = try await roundtripHTML(from: "<p>Простой текст</p>")
        XCTAssertEqual(html, "<p>Простой текст</p>")
    }

    func testRoundtripHeadingWithBold() async throws {
        let html = try await roundtripHTML(from: "<h1>Бе<strong>ри му</strong>ку</h1>")
        XCTAssertTrue(html.contains("<h1>"), "Expected <h1> in \(html)")
        XCTAssertTrue(html.contains("<strong>ри му</strong>"), "Expected strong text in \(html)")
    }

    func testRoundtripBulletList() async throws {
        let html = try await roundtripHTML(from: "<ul><li>Один</li><li>Два</li></ul>")
        XCTAssertTrue(html.contains("<ul>"), "Expected <ul> in \(html)")
        XCTAssertTrue(html.contains("<li><p>Один</p></li>"), "Expected list item paragraph in \(html)")
        XCTAssertTrue(html.contains("<li><p>Два</p></li>"))
    }

    func testRoundtripReplacesPreviousFragmentContent() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()
        try await doc.testApplyDescriptionDocument(RecipeDescriptionParser.parse("<p>Первый</p>"))
        try await doc.testApplyDescriptionDocument(RecipeDescriptionParser.parse("<p>Второй</p>"))
        let html = try await doc.testSerializedDescriptionHTML() ?? ""
        XCTAssertTrue(html.contains("Второй"), "Expected second content in \(html)")
        XCTAssertFalse(html.contains("Первый"), "First content should be replaced, got: \(html)")
    }

    // MARK: - Cross-document reload (yrs encode → yrs decode)

    func testEncodedStateDecodesIdentically() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()
        try await doc.testApplyDescriptionDocument(RecipeDescriptionParser.parse(khachapuriHTML))
        let originalHTML = try await doc.testSerializedDescriptionHTML() ?? ""

        guard let state = await doc.testEncodeStateAsUpdate() else {
            XCTFail("encodeStateAsUpdate returned nil")
            return
        }

        let reloaded = try YrsDocument(state: state)
        let reloadedHTML = try await reloaded.testSerializedDescriptionHTML() ?? ""

        XCTAssertEqual(originalHTML, reloadedHTML, "yrs state roundtrip should preserve description")

        // Dump for Node.js cross-library verification (yjs on web must decode the same tree).
        let path = "/tmp/yrs-test-native-html-import.bin"
        try state.write(to: URL(fileURLWithPath: path))
        print("Wrote \(state.count) bytes to \(path) — verify with: node scripts/test-yjs-description-roundtrip.mjs \(path)")
    }

    // MARK: - Helpers

    private func roundtripHTML(from html: String) async throws -> String {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()
        try await doc.testApplyDescriptionDocument(RecipeDescriptionParser.parse(html))
        let result = try await doc.testSerializedDescriptionHTML()
        return result ?? ""
    }
}
