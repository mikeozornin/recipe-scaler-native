import XCTest
import RecipeScalerCore

final class NativeRecipeImporterTests: XCTestCase {
    func testParseV10MinimalJson() throws {
        let json = """
        {
          "metadata": {
            "version": "1.0",
            "exportDate": "2026-06-16T12:00:00Z"
          },
          "recipes": [
            {
              "id": "legacy-1",
              "name": "Bread",
              "ingredients": [
                { "name": "flour" }
              ]
            }
          ]
        }
        """
        let url = try writeTempFile(named: "v10.json", contents: json)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try NativeRecipeImporter.parse(url: url)
        XCTAssertEqual(parsed.version, .v1_0)
        XCTAssertEqual(parsed.recipes.count, 1)
        XCTAssertEqual(parsed.recipes[0].name, "Bread")
        XCTAssertTrue(parsed.folders.isEmpty)
        XCTAssertTrue(parsed.imageEntries.isEmpty)
    }

    func testParseV12WithNutrition() throws {
        let json = """
        {
          "metadata": {
            "version": "1.2",
            "exportDate": "2026-06-16T12:00:00Z",
            "type": "recipes-v1.2",
            "count": 1
          },
          "recipes": [
            {
              "id": "r1",
              "name": "Salad",
              "ingredients": [],
              "nutrition": { "calories": 50, "protein": 2 }
            }
          ]
        }
        """
        let url = try writeTempFile(named: "v12.json", contents: json)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try NativeRecipeImporter.parse(url: url)
        XCTAssertEqual(parsed.version, .v1_2)
        XCTAssertEqual(parsed.recipes[0].nutrition?.calories, 50)
    }

    func testDetectVersionFromLegacyType() throws {
        let json = """
        {
          "metadata": {
            "version": "",
            "exportDate": "2026-06-16T12:00:00Z",
            "type": "recipes-simple"
          },
          "recipes": [
            { "id": "r1", "name": "Tea", "ingredients": [] }
          ]
        }
        """
        let url = try writeTempFile(named: "legacy.json", contents: json)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try NativeFormatDetector.detect(url: url), .v1_0)
    }

    func testDetectThrowsForNonObjectJson() throws {
        let json = "[1, 2, 3]"
        let url = try writeTempFile(named: "array.json", contents: json)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try NativeFormatDetector.detect(url: url)) { error in
            guard case NativeImportError.invalidJSON = error else {
                return XCTFail("Expected invalidJSON, got \(error)")
            }
        }
    }

    func testInvalidJsonThrows() throws {
        let url = try writeTempFile(named: "broken.json", contents: "{ not json")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try NativeRecipeImporter.parse(url: url)) { error in
            guard case NativeImportError.invalidJSON = error else {
                return XCTFail("Expected invalidJSON, got \(error)")
            }
        }
    }

    // MARK: - TP-4.3 Oversized JSON rejected (review #32)

    /// A native-export JSON larger than `maxRecipeJSONBytes` must be rejected with
    /// `.jsonSizeLimitExceeded` BEFORE `JSONDecoder` is called.
    func testTP4_3_RejectsOversizedJSON() throws {
        let big = String(repeating: "x", count: ThirdPartyImportLimits.maxRecipeJSONBytes + 1_000)
        // Format-valid envelope with a huge string field; decoder is not the target of this test.
        let json = """
        {
          "metadata": { "version": "1.3", "exportDate": "2026-06-18T12:00:00Z", "type": "recipes-v1.3" },
          "recipes": [ { "id": "r1", "name": "\(big)", "ingredients": [] } ]
        }
        """
        let url = try writeTempFile(named: "huge.json", contents: json)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try NativeRecipeImporter.parse(url: url)) { error in
            switch error as? NativeImportError {
            case .jsonSizeLimitExceeded:
                break
            default:
                XCTFail("Expected .jsonSizeLimitExceeded, got \(error)")
            }
        }
    }

    private func writeTempFile(named name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
