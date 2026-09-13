import XCTest
@testable import RecipeScalerNative

final class ProcessTableHashTests: XCTestCase {
    func testHashIgnoresIngredientName() {
        let flour = IngredientData(id: "flour", name: "Flour", originalAmount: "200", unit: "g")
        let renamed = IngredientData(id: "flour", name: "Wheat flour", originalAmount: "200", unit: "g")
        let html = "<ol><li>Mix dry</li><li>Bake</li></ol>"
        XCTAssertEqual(
            ProcessTableSourceHash.hash(ingredients: [flour], descriptionHtml: html),
            ProcessTableSourceHash.hash(ingredients: [renamed], descriptionHtml: html)
        )
    }

    func testHashChangesWhenOriginalAmountChanges() {
        let a = IngredientData(id: "flour", name: "Flour", originalAmount: "200", unit: "g")
        let b = IngredientData(id: "flour", name: "Flour", originalAmount: "250", unit: "g")
        let html = "<ol><li>Mix dry</li></ol>"
        XCTAssertNotEqual(
            ProcessTableSourceHash.hash(ingredients: [a], descriptionHtml: html),
            ProcessTableSourceHash.hash(ingredients: [b], descriptionHtml: html)
        )
    }

    func testCanonicalJSONMatchesJavaScriptKeyOrder() {
        let json = ProcessTableSourceHash.canonicalize(
            ingredients: [.init(id: "flour", originalAmount: 200, unit: "g")],
            steps: ["Mix dry", "Bake"]
        )
        XCTAssertEqual(
            json,
            #"{"ingredients":[{"id":"flour","originalAmount":200,"unit":"g"}],"steps":["Mix dry","Bake"]}"#
        )
        XCTAssertEqual(
            ProcessTableSourceHash.compute(
                ingredients: [.init(id: "flour", originalAmount: 200, unit: "g")],
                steps: ["Mix dry", "Bake"]
            ),
            "bda43ba6ff1804a016cd2a04899dd1ca49143a12c5fe95d5a295d805f9e6c882"
        )
    }

    func testExtractsLiThenFallsBackToParagraphs() {
        let steps = ProcessTableSourceHash.extractSteps(from: "<p>One</p><p>Two</p>")
        XCTAssertEqual(steps.map(\.text), ["One", "Two"])
        let fromList = ProcessTableSourceHash.extractSteps(from: "<ol><li>A</li><li>B</li></ol><p>ignored</p>")
        XCTAssertEqual(fromList.map(\.text), ["A", "B"])
    }

    func testRootLevelTimerParagraphIsHashedAsAStep() {
        let html = #"<p>Bake</p><p><span class="timer-reference">60 minutes</span></p><p>Cool</p>"#
        XCTAssertEqual(
            ProcessTableSourceHash.extractSteps(from: html).map(\.text),
            ["Bake", "60 minutes", "Cool"]
        )
        let orphaned = #"<p>Bake</p><span class="timer-reference">60 minutes</span><p>Cool</p>"#
        XCTAssertEqual(
            ProcessTableSourceHash.extractSteps(from: orphaned).map(\.text),
            ["Bake", "Cool"]
        )
    }

    func testExtractedStepTextUsesIngredientSpanAmountNotLabel() {
        let html = #"<p>Add <span class="ingredient-reference" data-ingredient-id="flour" data-original-amount="200">200</span> and mix</p>"#
        XCTAssertEqual(
            ProcessTableSourceHash.extractSteps(from: html).map(\.text),
            ["Add 200 and mix"]
        )
    }

    func testSerializedIngredientNodeHashesLikeTipTapAmountOnlySpan() {
        let flour = IngredientData(id: "flour", name: "Wheat flour", originalAmount: "200", unit: "g")
        let xml = #"<paragraph>Add <ingredient data-ingredient-id="flour" data-original-amount="200" data-ratio="1"/> and mix</paragraph>"#
        let html = XmlFragmentToHTML.html(fromSerializedXML: xml, ingredients: [flour]) ?? ""
        XCTAssertTrue(html.contains("class=\"ingredient-reference\""), html)
        XCTAssertTrue(html.contains(">200</span>"), html)
        XCTAssertFalse(html.contains("Wheat flour"), html)
        XCTAssertFalse(html.contains(" g "), html)
        XCTAssertEqual(
            ProcessTableSourceHash.extractSteps(from: html).map(\.text),
            ["Add 200 and mix"]
        )
    }
}
