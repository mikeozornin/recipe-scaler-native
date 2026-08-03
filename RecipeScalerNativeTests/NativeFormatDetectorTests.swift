//
//  NativeFormatDetectorTests.swift
//
//  Spec 057 T008 — verifies `NativeFormatDetector.detect(url:)` understands
//  the `.recipe` extension (alias for ZIP archive of the v1.4 format).
//

import XCTest
import ZIPFoundation
@testable import RecipeScalerCore

final class NativeFormatDetectorTests: XCTestCase {

    func test_detect_recipeExtension_returnsV1_4() throws {
        let url = try makeRecipeFile(version: "1.4", extension: "recipe")
        defer { try? FileManager.default.removeItem(at: url) }

        let version = try NativeFormatDetector.detect(url: url)

        XCTAssertEqual(version, .v1_4)
    }

    func test_detect_recipeExtensionWithoutImages_returnsV1_4() throws {
        let url = try makeRecipeFile(
            version: "1.4",
            extension: "recipe",
            includeImages: false
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let version = try NativeFormatDetector.detect(url: url)

        XCTAssertEqual(version, .v1_4)
    }

    func test_detect_recipeExtensionLegacyV1_0_returnsV1_0() throws {
        let url = try makeRecipeFile(
            version: nil,
            type: nil,
            extension: "recipe"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let version = try NativeFormatDetector.detect(url: url)

        XCTAssertEqual(version, .v1_0)
    }

    // MARK: - Helpers

    /// Build a `.recipe` (or `.zip`) file containing a single-recipe v1.x
    /// payload, optionally with placeholder images.
    private func makeRecipeFile(
        version: String?,
        type: String? = "recipes-v1.4",
        extension fileExtension: String,
        includeImages: Bool = true
    ) throws -> URL {
        let recipeId = "test-recipe-id"
        var metadata: [String: Any] = [:]
        metadata["count"] = 1
        metadata["exportDate"] = "2026-08-02T22:00:00Z"
        if let version { metadata["version"] = version }
        if let type { metadata["type"] = type }

        let recipe: [String: Any] = [
            "id": recipeId,
            "name": "Test Recipe",
            "ingredients": [[String: Any]](),
            "color": "#FF0000"
        ]

        let payload: [String: Any] = [
            "metadata": metadata,
            "recipes": [recipe]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).\(fileExtension)")

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "NativeFormatDetectorTests", code: 1)
        }
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(jsonData.count),
            compressionMethod: .deflate
        ) { position, size in
            jsonData.subdata(in: Int(position)..<Int(position + size))
        }

        if includeImages {
            let dummyFull = Data(repeating: 0xFF, count: 16)
            let dummyPreview = Data(repeating: 0xCC, count: 8)
            try archive.addEntry(
                with: "images/\(recipeId)/full.webp",
                type: .file,
                uncompressedSize: UInt32(dummyFull.count),
                compressionMethod: .deflate
            ) { position, size in
                dummyFull.subdata(in: Int(position)..<Int(position + size))
            }
            try archive.addEntry(
                with: "images/\(recipeId)/preview.webp",
                type: .file,
                uncompressedSize: UInt32(dummyPreview.count),
                compressionMethod: .deflate
            ) { position, size in
                dummyPreview.subdata(in: Int(position)..<Int(position + size))
            }
        }

        return url
    }
}
