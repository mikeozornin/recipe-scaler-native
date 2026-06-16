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

    func testInvalidJsonThrows() throws {
        let url = try writeTempFile(named: "broken.json", contents: "{ not json")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try NativeRecipeImporter.parse(url: url)) { error in
            guard case NativeImportError.invalidJSON = error else {
                return XCTFail("Expected invalidJSON, got \(error)")
            }
        }
    }

    private func writeTempFile(named name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
