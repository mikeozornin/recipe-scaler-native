import XCTest
@testable import RecipeScalerNative

final class ClipboardImportCandidateTests: XCTestCase {
    func testUrlOnlySingleHttps() {
        let candidate = ClipboardImportCandidate.make(fromPlainText: "https://example.com/recipe")
        XCTAssertEqual(candidate?.urls, ["https://example.com/recipe"])
    }

    func testUrlOnlyMultipleSeparatedByNewlines() {
        let text = "https://a.example/r1\nhttps://b.example/r2"
        let candidate = ClipboardImportCandidate.make(fromPlainText: text)
        XCTAssertEqual(candidate?.urls, ["https://a.example/r1", "https://b.example/r2"])
    }

    func testMixedLookPlusUrlIsRejected() {
        XCTAssertNil(ClipboardImportCandidate.make(fromPlainText: "посмотри https://example.com/r"))
    }

    func testPlainRecipeTextIsRejected() {
        XCTAssertNil(ClipboardImportCandidate.make(fromPlainText: "мука 200 г\nвода 100 мл"))
    }

    func testTwentySixUrlsRejected() {
        let urls = (1...26).map { "https://example.com/\($0)" }.joined(separator: "\n")
        XCTAssertNil(ClipboardImportCandidate.make(fromPlainText: urls))
    }

    func testTwentyFiveUrlsAccepted() {
        let urls = (1...25).map { "https://example.com/\($0)" }
        let candidate = ClipboardImportCandidate.make(fromPlainText: urls.joined(separator: "\n"))
        XCTAssertEqual(candidate?.urls.count, 25)
    }

    func testIdentityUsesClassifierOrder() {
        let a = ClipboardImportCandidate.make(fromPlainText: "https://one.example/\nhttps://two.example/")
        let b = ClipboardImportCandidate.make(fromPlainText: "https://one.example/ https://two.example/")
        XCTAssertEqual(a, b)
    }
}
