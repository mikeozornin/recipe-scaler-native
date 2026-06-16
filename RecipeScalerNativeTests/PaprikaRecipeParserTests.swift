import XCTest
import RecipeScalerCore

final class PaprikaRecipeParserTests: XCTestCase {
    func testParseMinimalFixture() throws {
        let fixtureURL = try fixtureURL(named: "paprika-minimal", ext: "paprikarecipe")
        let expected = try loadExpected(named: "paprika-minimal")
        let data = try Data(contentsOf: fixtureURL)

        let draft = try PaprikaRecipeParser.parse(
            gzipData: data,
            fileName: fixtureURL.lastPathComponent,
            sourceFormat: .paprikaSingle
        )

        XCTAssertEqual(draft.name, expected["name"] as? String)
        XCTAssertEqual(draft.ingredients.count, expected["ingredientCount"] as? Int)
        XCTAssertEqual(countOrderedListItems(in: draft.descriptionBlocks), expected["stepCount"] as? Int)
        XCTAssertEqual(draft.servings, 4)
        XCTAssertEqual(draft.originalRecipe, "Test Kitchen")
        XCTAssertEqual(draft.originalRecipeLink, "https://example.com/recipe")
        XCTAssertEqual(draft.categoryLabels, ["Dinner", "Quick"])
        XCTAssertEqual(draft.ingredients[0].amount, "200")
        XCTAssertEqual(draft.ingredients[0].unit, "g")
        XCTAssertEqual(draft.ingredients[0].name, "flour")
        XCTAssertEqual(draft.ingredients[2].name, "salt")
    }

    func testParseStripsStepNumbers() throws {
        let fixtureURL = try fixtureURL(named: "paprika-minimal", ext: "paprikarecipe")
        let data = try Data(contentsOf: fixtureURL)
        let draft = try PaprikaRecipeParser.parse(
            gzipData: data,
            fileName: fixtureURL.lastPathComponent,
            sourceFormat: .paprikaSingle
        )

        let steps = draft.descriptionBlocks.compactMap { block -> String? in
            if case let .orderedListItem(text) = block { return text }
            return nil
        }
        XCTAssertEqual(steps, ["Mix flour and eggs.", "Bake for 30 minutes."])
    }

    /// T063 [US7]: prep_time / cook_time / notes must be emitted as paragraph
    /// blocks BEFORE the ordered list of steps so they appear as a metadata prefix.
    func testMetadataFieldsBecomeParagraphPrefix() throws {
        let payload: [String: Any] = [
            "name": "Bowl",
            "servings": "2",
            "ingredients": "oats",
            "prep_time": "10 min",
            "cook_time": "20 min",
            "notes": "Rest overnight",
            "directions": "1. Combine.\n2. Eat."
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let draft = try PaprikaRecipeParser.parse(
            jsonData: data,
            fileName: "bowl.paprikarecipe",
            sourceFormat: .paprikaSingle
        )

        // The first three blocks should be the metadata paragraphs in order.
        let prefix = Array(draft.descriptionBlocks.prefix(3))
        XCTAssertEqual(prefix, [
            .paragraph("Prep: 10 min"),
            .paragraph("Cook: 20 min"),
            .paragraph("Rest overnight")
        ])
    }

    /// T063 [US7]: source / source_url survive into draft fields.
    func testSourceFieldsPreserved() throws {
        let payload: [String: Any] = [
            "name": "X",
            "ingredients": "egg",
            "source": "Bon Appétit",
            "source_url": "https://example.com/x"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let draft = try PaprikaRecipeParser.parse(
            jsonData: data,
            fileName: "x.paprikarecipe",
            sourceFormat: .paprikaSingle
        )
        XCTAssertEqual(draft.originalRecipe, "Bon Appétit")
        XCTAssertEqual(draft.originalRecipeLink, "https://example.com/x")
    }

    private func countOrderedListItems(in blocks: [DescriptionBlock]) -> Int {
        blocks.reduce(into: 0) { count, block in
            if case .orderedListItem = block { count += 1 }
        }
    }

    private func fixtureURL(named name: String, ext: String) throws -> URL {
        let bundle = Bundle(for: PaprikaRecipeParserTests.self)
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "ThirdPartyImport"
        ) else {
            throw NSError(domain: "PaprikaRecipeParserTests", code: 1)
        }
        return url
    }

    private func loadExpected(named name: String) throws -> [String: Any] {
        let bundle = Bundle(for: PaprikaRecipeParserTests.self)
        guard let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "ThirdPartyImport/expected"
        ) else {
            throw NSError(domain: "PaprikaRecipeParserTests", code: 2)
        }
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
