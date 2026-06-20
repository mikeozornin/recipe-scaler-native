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
        XCTAssertEqual(draft.ingredients[0].unit, "grams")
        XCTAssertEqual(draft.ingredients[0].name, "Cucumber")
        XCTAssertEqual(draft.ingredients[1].amount, "2")
        XCTAssertEqual(draft.ingredients[1].unit, "tablespoons")
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

    /// T063 [US7]: numeric `duration` (Int / NSNumber minutes) is emitted as a
    /// `.durationMinutes` structural block (Native layer renders a localized
    /// paragraph via `DescriptionBlockLocalizer` — see review #30).
    func testDurationIntBecomesMinutesSignal() throws {
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
        XCTAssertEqual(draft.descriptionBlocks.first, .durationMinutes(10))
    }

    /// T063 [US7]: `cookingDuration` is used when `duration` is absent,
    /// and a string `rawDifficulty` is appended as a `.difficulty` structural block.
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
            .durationMinutes(30),
            .difficulty("Easy")
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
        XCTAssertEqual(draft.descriptionBlocks.first, .durationMinutes(15))
    }

    /// Real Crouton export (2 recipes, one with non-ASCII filename).
    /// Verifies detection, enumeration and parser tolerance to mixed schemas.
    func testRealExportDetectAndEnumerate() async throws {
        let url = try fixtureURL(named: "crouton-real-export", ext: "zip")
        let format = try ThirdPartyFormatDetector.detect(url: url)
        XCTAssertEqual(format, .croutonArchive)

        let entries = try await ThirdPartyFormatDetector.enumerateRecipeEntries(
            url: url,
            format: .croutonArchive
        )
        XCTAssertEqual(entries.count, 2)

        try ThirdPartyFormatDetector.validateEntryCount(entries)

        let names = entries.map(\.fileName).sorted()
        XCTAssertTrue(names.contains(where: { $0.lowercased().hasSuffix("chocolate chip cookies.crumb") }))
    }

    func testRealExportParsesFirstRecipe() async throws {
        let url = try fixtureURL(named: "crouton-real-export", ext: "zip")
        let entries = try await ThirdPartyFormatDetector.enumerateRecipeEntries(
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

    /// Debug session 6eea62: Crouton uses singular quantityType values (CUP, TEASPOON).
    /// MIK-145 [review #62]: no canonicalization — the raw `quantityType` is
    /// preserved lowercased (no `CUP → cup`, no `ITEM → ""` collapse).
    func testRealExportParsesIngredientUnits() async throws {
        let url = try fixtureURL(named: "crouton-real-export", ext: "zip")
        let entries = try await ThirdPartyFormatDetector.enumerateRecipeEntries(
            url: url,
            format: .croutonArchive
        )
        guard let cookieEntry = entries.first(where: { $0.fileName.lowercased().contains("chocolate chip") }) else {
            throw NSError(domain: "CroutonRecipeParserTests", code: 99)
        }
        let draft = try CroutonRecipeParser.parse(
            jsonData: cookieEntry.data,
            fileName: cookieEntry.fileName,
            sourceFormat: .croutonArchive
        )
        let butter = draft.ingredients.first { $0.name.contains("butter") }
        let flour = draft.ingredients.first { $0.name.contains("flour") }
        let eggs = draft.ingredients.first { $0.name.contains("eggs") }
        XCTAssertEqual(butter?.amount, "1")
        XCTAssertEqual(butter?.unit, "cup")
        XCTAssertEqual(flour?.amount, "3")
        XCTAssertEqual(flour?.unit, "cup")
        XCTAssertEqual(eggs?.amount, "2")
        XCTAssertEqual(eggs?.unit, "item")
        let vanilla = draft.ingredients.first { $0.name.contains("vanilla") }
        XCTAssertEqual(vanilla?.unit, "teaspoon")
    }

    func testRealExportHandlesNonASCIIRecipe() async throws {
        let url = try fixtureURL(named: "crouton-real-export", ext: "zip")
        let entries = try await ThirdPartyFormatDetector.enumerateRecipeEntries(
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

    // MARK: - TP-4.2 Oversized JSON rejected (review #32)

    /// A Crouton JSON payload exceeding `maxRecipeJSONBytes` must be rejected with
    /// `.jsonSizeLimitExceeded` BEFORE `JSONSerialization` is called.
    func testTP4_2_RejectsOversizedJSON() throws {
        let big = String(repeating: "x", count: ThirdPartyImportLimits.maxRecipeJSONBytes + 1_000)
        let payload = "{\"uuid\":\"x\",\"name\":\"\(big)\",\"ingredients\":[]}"
        let data = Data(payload.utf8)
        XCTAssertGreaterThan(data.count, ThirdPartyImportLimits.maxRecipeJSONBytes)

        XCTAssertThrowsError(
            try CroutonRecipeParser.parse(
                jsonData: data,
                fileName: "huge.crumb",
                sourceFormat: .croutonSingle
            )
        ) { error in
            guard case .jsonSizeLimitExceeded(let fileName) = error as? ThirdPartyImportError else {
                return XCTFail("Expected .jsonSizeLimitExceeded, got \(error)")
            }
            XCTAssertEqual(fileName, "huge.crumb")
        }
    }

    // MARK: - TP-14 Int(amountValue) overflow safety (review #14)

    /// TP14 [review #14]: oversized integer amount out of Int64 range must not
    /// crash the import — falls back to String representation.
    func testTP14_IntegerOverflowDoesNotCrash() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "Big",
            "ingredients": [[
                "order": 0,
                "ingredient": ["name": "salt"],
                "quantity": ["amount": 1e20, "quantityType": "GRAMS"]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "big.crumb",
            sourceFormat: .croutonSingle
        )

        XCTAssertEqual(draft.ingredients.count, 1)
        XCTAssertEqual(draft.ingredients[0].amount, "1e+20")
        XCTAssertEqual(draft.ingredients[0].unit, "grams")
    }

    /// TP14 [review #14]: integer amount at the upper edge of Int64 range is
    /// still formatted losslessly as Int (no scientific notation).
    func testTP14_LargeIntegerInRangeFormatsAsInt() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "Edge",
            "ingredients": [[
                "order": 0,
                "ingredient": ["name": "salt"],
                "quantity": ["amount": 9_000_000_000.0, "quantityType": "GRAMS"]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "edge.crumb",
            sourceFormat: .croutonSingle
        )

        XCTAssertEqual(draft.ingredients[0].amount, "9000000000")
    }

    /// TP14 [review #14]: negative value within Int64 still formats as Int.
    func testTP14_NegativeIntegerAmountFormatsAsInt() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "Neg",
            "ingredients": [[
                "order": 0,
                "ingredient": ["name": "x"],
                "quantity": ["amount": -5.0, "quantityType": "GRAMS"]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "neg.crumb",
            sourceFormat: .croutonSingle
        )

        XCTAssertEqual(draft.ingredients[0].amount, "-5")
    }

    /// TP14 [review #14]: regression — normal integer amount still becomes
    /// "225" without a decimal dot (existing format preserved).
    func testTP14_NormalIntegerAmountStillFormatsWithoutDot() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "Normal",
            "ingredients": [[
                "order": 0,
                "ingredient": ["name": "flour"],
                "quantity": ["amount": 225.0, "quantityType": "GRAMS"]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "normal.crumb",
            sourceFormat: .croutonSingle
        )

        XCTAssertEqual(draft.ingredients[0].amount, "225")
    }

    /// TP14 [review #14]: fractional amount is still rendered via String(Double)
    /// (no rounding, no scientific notation for in-range values).
    func testTP14_FractionalAmountStillUsesStringOfDouble() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "Frac",
            "ingredients": [[
                "order": 0,
                "ingredient": ["name": "milk"],
                "quantity": ["amount": 2.5, "quantityType": "CUPS"]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "frac.crumb",
            sourceFormat: .croutonSingle
        )

        XCTAssertEqual(draft.ingredients[0].amount, "2.5")
    }

    /// MIK-119 [review #35]: empty `images` array must not set the flag — there
    /// is nothing to warn about. Also documents that the oversized-image branch
    /// is unreachable through a valid JSON payload today —
    /// `maxRecipeJSONBytes` (16 MB) < `maxImageBytes` (25 MB), so oversized
    /// images are rejected earlier with `.jsonSizeLimitExceeded`
    /// (covered by `testTP4_2_RejectsOversizedJSON`). The `imageOversized`
    /// guard stays as defense-in-depth.
    func testMIK119_NoImagesDoesNotSetFlag() throws {
        let payload: [String: Any] = [
            "uuid": "x",
            "name": "No Images",
            "ingredients": [["order": 0, "ingredient": ["name": "x"]]],
            "images": []
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "noimg.crumb",
            sourceFormat: .croutonSingle
        )

        XCTAssertNil(draft.imageData)
        XCTAssertFalse(draft.imageOversized)
    }

    /// MIK-119 [review #35]: a small valid first image must produce both
    /// `imageData` and `imageOversized == false`. Guards against regressions
    /// where a decoded photo also gets flagged as oversized.
    func testMIK119_ValidImageDecodesAndDoesNotFlagOversized() throws {
        let tinyJPEGBase64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oACAEBAAA/APvSiiig/9k="
        let payload: [String: Any] = [
            "uuid": "img",
            "name": "Photo Bowl",
            "ingredients": [["order": 0, "ingredient": ["name": "x"]]],
            "images": [tinyJPEGBase64]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let draft = try CroutonRecipeParser.parse(
            jsonData: data,
            fileName: "photo.crumb",
            sourceFormat: .croutonSingle
        )

        XCTAssertNotNil(draft.imageData)
        XCTAssertFalse(draft.imageOversized)
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
