import XCTest
import RecipeScalerCore

final class CroutonRecipeParserTests: XCTestCase {
    func testParseMinimalFixture() throws {
        let fixtureURL = try fixtureURL(named: "crouton-minimal", ext: "crumb")
        let expected = try loadExpected(named: "crouton-minimal")
        let data = try Data(contentsOf: fixtureURL)

        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: fixtureURL.lastPathComponent,
            sourceFormat: .croutonSingle
        )

        XCTAssertEqual(draft.name, expected["name"] as? String)
        XCTAssertEqual(draft.ingredients.count, expected["ingredientCount"] as? Int)
        XCTAssertEqual(countOrderedListItems(in: draft.descriptionBlocks), expected["stepCount"] as? Int)
        XCTAssertEqual(draft.servings, 2)
        XCTAssertEqual(draft.ingredients[0].amount, "225")
        XCTAssertEqual(draft.ingredients[0].unit, "g")
        XCTAssertEqual(draft.ingredients[0].name, "Cucumber")
        XCTAssertEqual(draft.ingredients[1].amount, "2")
        XCTAssertEqual(draft.ingredients[1].unit, "tbsp")
    }

    func testSectionStepBecomesHeading() throws {
        let fixtureURL = try fixtureURL(named: "crouton-minimal", ext: "crumb")
        let data = try Data(contentsOf: fixtureURL)
        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: fixtureURL.lastPathComponent,
            sourceFormat: .croutonSingle
        )

        let headings = draft.descriptionBlocks.compactMap { block -> String? in
            if case let .heading(_, text) = block { return text }
            return nil
        }
        XCTAssertEqual(headings, ["Dressing"])
    }

    /// T063 [US7]: numeric `duration` (Int / NSNumber minutes) is rendered as
    /// an "N min" paragraph before the steps.
    func testDurationIntBecomesMinutesParagraph() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "Cookies",
            "serves": 12,
            "duration": 10,
            "ingredients": [["order": 0, "ingredient": ["name": "flour"]]],
            "steps": [["order": 0, "step": "Bake"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "cookies.crumb",
            sourceFormat: .croutonSingle
        )
        XCTAssertEqual(draft.descriptionBlocks.first, .paragraph("10 min"))
    }

    /// T063 [US7]: `cookingDuration` is used when `duration` is absent,
    /// and a string `rawDifficulty` is appended as a separate paragraph.
    func testCookingDurationAndDifficultyPrefix() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "Salad",
            "serves": 4,
            "cookingDuration": 30,
            "rawDifficulty": "Easy",
            "ingredients": [["order": 0, "ingredient": ["name": "leaves"]]],
            "steps": [["order": 0, "step": "Toss"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "salad.crumb",
            sourceFormat: .croutonSingle
        )
        let prefix = Array(draft.descriptionBlocks.prefix(2))
        XCTAssertEqual(prefix, [
            .paragraph("30 min"),
            .paragraph("Easy")
        ])
    }

    /// T063 [US7]: when both duration and cookingDuration are present,
    /// duration wins; cookingDuration is ignored.
    func testDurationWinsOverCookingDuration() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "Dual",
            "serves": 1,
            "duration": 15,
            "cookingDuration": 45,
            "ingredients": [["order": 0, "ingredient": ["name": "x"]]],
            "steps": [["order": 0, "step": "Go"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "dual.crumb",
            sourceFormat: .croutonSingle
        )
        XCTAssertEqual(draft.descriptionBlocks.first, .paragraph("15 min"))
    }

    /// Real Crouton export (2 recipes, one with non-ASCII filename).
    /// Verifies detection, enumeration and parser tolerance to mixed schemas.
    func testRealExportDetectAndEnumerate() throws {
        let url = try fixtureURL(named: "crouton-real-export", ext: "zip")
        let format = try ThirdPartyFormatDetector.detect(url: url)
        XCTAssertEqual(format, .croutonArchive)

        let entries = try ThirdPartyFormatDetector.enumerateRecipeEntries(
            url: url,
            format: .croutonArchive
        )
        XCTAssertEqual(entries.count, 2)

        try ThirdPartyFormatDetector.validateEntryCount(entries)

        let names = entries.map(\.fileName).sorted()
        XCTAssertTrue(names.contains(where: { $0.lowercased().hasSuffix("chocolate chip cookies.crumb") }))
    }

    func testRealExportParsesFirstRecipe() throws {
        let url = try fixtureURL(named: "crouton-real-export", ext: "zip")
        let entries = try ThirdPartyFormatDetector.enumerateRecipeEntries(
            url: url,
            format: .croutonArchive
        )
        guard let cookieEntry = entries.first(where: { $0.fileName.lowercased().contains("chocolate chip") }) else {
            throw NSError(
                domain: "CroutonRecipeParserTests",
                code: 99,
                userInfo: [NSLocalizedDescriptionKey: "missing chocolate chip entry"]
            )
        }
        let draft = try CroutonRecipeParser.parse(
            jsonData: cookieEntry.data,
            fileName: cookieEntry.fileName,
            sourceFormat: .croutonArchive
        )

        XCTAssertEqual(draft.name, "Chocolate Chip Cookies")
        XCTAssertEqual(draft.servings, 12)
        XCTAssertFalse(draft.ingredients.isEmpty)
        XCTAssertEqual(countOrderedListItems(in: draft.descriptionBlocks), 10)
        XCTAssertNotNil(draft.imageData)
        XCTAssertTrue(draft.imageData?.count ?? 0 <= ThirdPartyImportLimits.maxImageBytes)
    }

    func testRealExportHandlesNonASCIIRecipe() throws {
        let url = try fixtureURL(named: "crouton-real-export", ext: "zip")
        let entries = try ThirdPartyFormatDetector.enumerateRecipeEntries(
            url: url,
            format: .croutonArchive
        )
        // Real-world Crouton bug: filename bytes are valid UTF-8 but the UTF-8
        // general-purpose bit flag is NOT set in the ZIP central directory.
        // Our detector forces UTF-8 decoding so the Cyrillic name survives.
        guard let target = entries.first(where: { $0.fileName == "Домашнее мороженое.crumb" }) else {
            let names = entries.map(\.fileName)
            throw NSError(
                domain: "CroutonRecipeParserTests",
                code: 99,
                userInfo: [NSLocalizedDescriptionKey: "missing Cyrillic entry; got: \(names)"]
            )
        }
        let draft = try CroutonRecipeParser.parse(
            jsonData: target.data,
            fileName: target.fileName,
            sourceFormat: .croutonArchive
        )
        XCTAssertEqual(draft.servings, 8)
        XCTAssertFalse(draft.ingredients.isEmpty)
        XCTAssertEqual(countOrderedListItems(in: draft.descriptionBlocks), 7)
        XCTAssertEqual(draft.sourceFileName, "Домашнее мороженое.crumb")
    }

    /// T058 [US6]: tiny 1×1 JPEG inside a Crouton .crumb is decoded into
    /// `ThirdPartyRecipeDraft.imageData` byte-for-byte.
    func testTinyJPEGFixtureDecodes() throws {
        let url = try fixtureURL(named: "crouton-with-photo", ext: "crumb")
        let data = try Data(contentsOf: url)
        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: url.lastPathComponent,
            sourceFormat: .croutonSingle
        )

        XCTAssertEqual(draft.name, "Photo Bowl")
        XCTAssertNotNil(draft.imageData)
        XCTAssertEqual(draft.imageData?.count, 127)
    }

    private func countOrderedListItems(in blocks: [DescriptionBlock]) -> Int {
        blocks.reduce(into: 0) { count, block in
            if case .orderedListItem = block { count += 1 }
        }
    }

    private func fixtureURL(named name: String, ext: String) throws -> URL {
        let bundle = Bundle(for: CroutonRecipeParserTests.self)
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "ThirdPartyImport"
        ) else {
            throw NSError(domain: "CroutonRecipeParserTests", code: 1)
        }
        return url
    }

    private func loadExpected(named name: String) throws -> [String: Any] {
        let bundle = Bundle(for: CroutonRecipeParserTests.self)
        guard let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "ThirdPartyImport/expected"
        ) else {
            throw NSError(domain: "CroutonRecipeParserTests", code: 2)
        }
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
