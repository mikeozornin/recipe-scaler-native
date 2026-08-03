import XCTest
import ZIPFoundation
import RecipeScalerCore

final class ThirdPartyFormatDetectorTests: XCTestCase {
    func testDetectPaprikaSingle() throws {
        let url = try fixtureURL(named: "paprika-minimal", ext: "paprikarecipe")
        XCTAssertEqual(try ThirdPartyFormatDetector.detect(url: url), .paprikaSingle)
    }

    func testDetectPaprikaArchive() throws {
        let url = try fixtureURL(named: "paprika-three", ext: "paprikarecipes")
        XCTAssertEqual(try ThirdPartyFormatDetector.detect(url: url), .paprikaArchive)
    }

    func testDetectCroutonSingle() throws {
        let url = try fixtureURL(named: "crouton-minimal", ext: "crumb")
        XCTAssertEqual(try ThirdPartyFormatDetector.detect(url: url), .croutonSingle)
    }

    func testDetectCroutonArchive() throws {
        let url = try fixtureURL(named: "crouton-batch", ext: "zip")
        XCTAssertEqual(try ThirdPartyFormatDetector.detect(url: url), .croutonArchive)
    }

    func testEnumeratePaprikaArchive() async throws {
        let url = try fixtureURL(named: "paprika-three", ext: "paprikarecipes")
        let entries = try await ThirdPartyFormatDetector.enumerateRecipeEntries(
            url: url,
            format: .paprikaArchive
        )
        let expected = try loadExpected(named: "paprika-three")
        XCTAssertEqual(entries.count, expected["recipeCount"] as? Int)
    }

    func testEnumerateCroutonArchive() async throws {
        let url = try fixtureURL(named: "crouton-batch", ext: "zip")
        let entries = try await ThirdPartyFormatDetector.enumerateRecipeEntries(
            url: url,
            format: .croutonArchive
        )
        let expected = try loadExpected(named: "crouton-batch")
        XCTAssertEqual(entries.count, expected["recipeCount"] as? Int)
    }

    func testUnsupportedTextFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("unsupported.txt")
        try "not a recipe".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try ThirdPartyFormatDetector.detect(url: url), .unsupported)
    }

    func testMixedArchiveIsUnsupported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mixed-\(UUID().uuidString).zip")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        defer { try? fileManager.removeItem(at: url) }

        let paprikaData = try Data(contentsOf: try fixtureURL(named: "paprika-minimal", ext: "paprikarecipe"))
        let crumbData = try Data(contentsOf: try fixtureURL(named: "crouton-minimal", ext: "crumb"))

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "ThirdPartyFormatDetectorTests", code: 3)
        }
        try archive.addEntry(
            with: "recipe.paprikarecipe",
            type: .file,
            uncompressedSize: UInt32(paprikaData.count),
            provider: { position, size in
                paprikaData.subdata(in: Int(position)..<Int(position + size))
            }
        )
        try archive.addEntry(
            with: "recipe.crumb",
            type: .file,
            uncompressedSize: UInt32(crumbData.count),
            provider: { position, size in
                crumbData.subdata(in: Int(position)..<Int(position + size))
            }
        )

        XCTAssertEqual(try ThirdPartyFormatDetector.detect(url: url), .unsupported)
    }

    func testRecipeLimitExceeded() throws {
        let entries = (0..<501).map { index in
            ThirdPartyArchiveEntry(fileName: "recipe-\(index).paprikarecipe", data: Data())
        }
        XCTAssertThrowsError(try ThirdPartyFormatDetector.validateEntryCount(entries)) { error in
            XCTAssertEqual(error as? ThirdPartyImportError, .recipeLimitExceeded(limit: 500))
        }
    }

    /// Spec 057 T009 — `.recipe` files are the native Recipe Scaler format,
    /// not third-party. They are detected via `NativeFormatDetector`, so the
    /// third-party detector must report them as `.unsupported`.
    func testDetectRecipeScalerNativeIsUnsupported() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-\(UUID().uuidString).recipe")
        defer { try? FileManager.default.removeItem(at: url) }

        let recipeId = "test-native"
        let payload: [String: Any] = [
            "metadata": [
                "version": "1.4",
                "type": "recipes-v1.4",
                "count": 1,
                "exportDate": "2026-08-02T22:00:00Z"
            ],
            "recipes": [[
                "id": recipeId,
                "name": "Native Recipe",
                "ingredients": [[String: Any]](),
                "color": "#FF0000"
            ]]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "ThirdPartyFormatDetectorTests", code: 4)
        }
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(jsonData.count),
            compressionMethod: .deflate
        ) { position, size in
            jsonData.subdata(in: Int(position)..<Int(position + size))
        }

        XCTAssertEqual(try ThirdPartyFormatDetector.detect(url: url), .unsupported)
    }

    private func fixtureURL(named name: String, ext: String) throws -> URL {
        let bundle = Bundle(for: ThirdPartyFormatDetectorTests.self)
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "ThirdPartyImport"
        ) else {
            throw NSError(domain: "ThirdPartyFormatDetectorTests", code: 1)
        }
        return url
    }

    private func loadExpected(named name: String) throws -> [String: Any] {
        let bundle = Bundle(for: ThirdPartyFormatDetectorTests.self)
        guard let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "ThirdPartyImport/expected"
        ) else {
            throw NSError(domain: "ThirdPartyFormatDetectorTests", code: 2)
        }
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
