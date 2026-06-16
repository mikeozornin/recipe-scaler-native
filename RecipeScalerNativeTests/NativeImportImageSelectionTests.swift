import XCTest
@testable import RecipeScalerCore

final class NativeImportImageSelectionTests: XCTestCase {

    func testPrefersFullOverPreview() {
        let entries = [
            entry(recipeId: "r1", kind: .preview, data: Data([1])),
            entry(recipeId: "r1", kind: .full, data: Data([2, 3])),
        ]
        if case .ready(let data) = NativeImportImagePicker.selection(from: entries) {
            XCTAssertEqual(data, Data([2, 3]))
        } else {
            XCTFail("expected .ready(full)")
        }
    }

    func testUsesPreviewWhenFullMissing() {
        let entries = [entry(recipeId: "r1", kind: .preview, data: Data([9]))]
        if case .ready(let data) = NativeImportImagePicker.selection(from: entries) {
            XCTAssertEqual(data, Data([9]))
        } else {
            XCTFail("expected .ready(preview)")
        }
    }

    func testEmptyEntriesReturnsNone() {
        XCTAssertEqual(NativeImportImagePicker.selection(from: []), .none)
    }

    func testTooLargeWhenOverLimit() {
        let entries = [entry(recipeId: "r1", kind: .full, data: Data(count: 100))]
        XCTAssertEqual(
            NativeImportImagePicker.selection(from: entries, maxBytes: 50),
            .tooLarge
        )
    }

    private func entry(
        recipeId: String,
        kind: NativeRecipeImporter.ImageEntry.ImageKind,
        data: Data
    ) -> NativeRecipeImporter.ImageEntry {
        NativeRecipeImporter.ImageEntry(
            recipeId: recipeId,
            kind: kind,
            data: data,
            relativePath: "images/\(recipeId)/\(kind.rawValue).webp"
        )
    }
}
