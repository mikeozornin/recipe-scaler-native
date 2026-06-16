import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

final class DescriptionXmlFragmentWriterTests: XCTestCase {
    func testWritesOrderedListSteps() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        let blocks: [DescriptionBlock] = [
            .paragraph("Prep: 15 min"),
            .orderedListItem("Mix flour and eggs."),
            .orderedListItem("Bake for 30 minutes.")
        ]

        try await doc.testApplyDescriptionBlocks(blocks)
        let html = try await doc.testSerializedDescriptionHTML()

        XCTAssertNotNil(html)
        XCTAssertTrue(html?.contains("Mix flour and eggs.") ?? false)
        XCTAssertTrue(html?.contains("Bake for 30 minutes.") ?? false)
        XCTAssertTrue(html?.contains("<ol>") ?? false)
    }

    func testWritesSectionHeading() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        let blocks: [DescriptionBlock] = [
            .orderedListItem("Chop cucumber"),
            .heading(level: 3, "Dressing"),
            .orderedListItem("Mix oil and vinegar")
        ]

        try await doc.testApplyDescriptionBlocks(blocks)
        let html = try await doc.testSerializedDescriptionHTML()

        XCTAssertNotNil(html)
        XCTAssertTrue(html?.contains("Dressing") ?? false)
    }
}
