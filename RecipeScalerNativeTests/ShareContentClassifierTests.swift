//
//  ShareContentClassifierTests.swift
//
//  Spec 025 T033 — pure-logic priority classification of Share attachments.
//

import XCTest
@testable import RecipeScalerCore

final class ShareContentClassifierTests: XCTestCase {

    // MARK: - URL > Images > Text

    func test_urlsPresent_textAbsent_returnsUrls() {
        let url = URL(string: "https://example.com/recipe")!
        let result = ShareContentClassifier.classify(
            urls: [url],
            texts: [],
            images: []
        )
        XCTAssertEqual(result, .urls([url]))
    }

    func test_urlsPresent_textPresent_returnsMixed() {
        let url = URL(string: "https://example.com")!
        let result = ShareContentClassifier.classify(
            urls: [url],
            texts: ["Bon appetit!"],
            images: []
        )
        XCTAssertEqual(result, .mixed(urls: [url], text: "Bon appetit!"))
    }

    func test_urlsAbsent_imagesPresent_returnsImages() {
        let item = ImportPhotoItem(
            data: Data([0xFF, 0xD8, 0xFF]),
            fileName: "a.jpg",
            utType: .jpeg
        )
        let result = ShareContentClassifier.classify(
            urls: [],
            texts: [],
            images: [item]
        )

        if case .images(let imgs) = result {
            XCTAssertEqual(imgs.count, 1)
            XCTAssertEqual(imgs.first?.fileName, "a.jpg")
        } else {
            XCTFail("expected .images, got \(result)")
        }
    }

    // MARK: - Text-only

    func test_textOnly_plainText_returnsText() {
        let result = ShareContentClassifier.classify(
            urls: [],
            texts: ["Boil water", "Add salt"],
            images: []
        )
        XCTAssertEqual(result, .text("Boil water\nAdd salt"))
    }

    func test_textOnly_singleUrl_returnsUrls() {
        // If the text is URL-only, ImportContentClassifier promotes it to URLs.
        let result = ShareContentClassifier.classify(
            urls: [],
            texts: ["https://example.com/recipe"],
            images: []
        )
        if case .urls(let urls) = result {
            XCTAssertEqual(urls, [URL(string: "https://example.com/recipe")!])
        } else {
            XCTFail("expected .urls from text-URL, got \(result)")
        }
    }

    // MARK: - Empty

    func test_allEmpty_returnsEmpty() {
        let result = ShareContentClassifier.classify(urls: [], texts: [], images: [])
        XCTAssertEqual(result, .empty)
    }

    func test_whitespaceOnlyText_returnsEmpty() {
        let result = ShareContentClassifier.classify(
            urls: [],
            texts: ["  \n\t "],
            images: []
        )
        XCTAssertEqual(result, .empty)
    }

    // MARK: - Priority

    func test_urlsWinOverImagesAndText() {
        let url = URL(string: "https://example.com")!
        let item = ImportPhotoItem(
            data: Data([0xFF, 0xD8]),
            fileName: "x.jpg",
            utType: .jpeg
        )
        let result = ShareContentClassifier.classify(
            urls: [url],
            texts: ["some text"],
            images: [item]
        )
        XCTAssertEqual(result, .mixed(urls: [url], text: "some text"))
    }

    func test_imagesWinOverTextWhenNoUrls() {
        let item = ImportPhotoItem(
            data: Data([0xFF, 0xD8]),
            fileName: "y.jpg",
            utType: .jpeg
        )
        let result = ShareContentClassifier.classify(
            urls: [],
            texts: ["Boil"],
            images: [item]
        )
        if case .images(let imgs) = result {
            XCTAssertEqual(imgs.count, 1)
        } else {
            XCTFail("expected .images, got \(result)")
        }
    }
}
