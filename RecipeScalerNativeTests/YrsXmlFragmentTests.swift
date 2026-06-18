//
//  YrsXmlFragmentTests.swift
//  RecipeScalerNativeTests
//

import XCTest
import YrsC
@testable import RecipeScalerNative

/// Round-trip coverage for `YrsXmlFragment` / `YrsXmlElement` / `YrsXmlText`
/// wrappers — insert via wrapper API, read back via wrapper API, verify content.
final class YrsXmlFragmentTests: XCTestCase {

    func testInsertAndReadParagraph() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        try await doc.testWriteTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else {
                XCTFail("fragment should exist after ensureRecipeCreateRoots")
                return
            }
            let paragraph = fragment.insertElem(at: 0, name: "paragraph", txn: txn)
            XCTAssertNotNil(paragraph)
            let text = paragraph?.insertText(at: 0, txn: txn)
            XCTAssertNotNil(text)
            text?.insert(at: 0, str: "Hello wrappers!", txn: txn)
        }

        let html = try await doc.testReadTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return nil as String? }
            return XmlFragmentToHTML.serializedFragment(from: fragment, txn: txn)
        }
        XCTAssertNotNil(html)
        XCTAssertTrue(html?.contains("Hello wrappers!") ?? false)
    }

    func testChildLenAndChildAccess() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        try await doc.testWriteTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            XCTAssertEqual(fragment.childLen(txn: txn), 0)
            fragment.insertElem(at: 0, name: "paragraph", txn: txn)
            fragment.insertElem(at: 1, name: "heading", txn: txn)
            XCTAssertEqual(fragment.childLen(txn: txn), 2)
        }

        try await doc.testReadTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else {
                XCTFail("fragment not found")
                return
            }
            XCTAssertEqual(fragment.childLen(txn: txn), 2)

            let first = fragment.child(at: 0, txn: txn)
            if case let .element(elem) = first {
                XCTAssertEqual(elem.tag(txn: txn), "paragraph")
            } else {
                XCTFail("first child should be element")
            }

            let second = fragment.child(at: 1, txn: txn)
            if case let .element(elem) = second {
                XCTAssertEqual(elem.tag(txn: txn), "heading")
            } else {
                XCTFail("second child should be element")
            }

            XCTAssertNil(fragment.child(at: 99, txn: txn))
        }
    }

    func testElementAttributes() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        try await doc.testWriteTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            let heading = fragment.insertElem(at: 0, name: "heading", txn: txn)
            heading?.insertAttr(key: "level", value: "3", txn: txn)
            let text = heading?.insertText(at: 0, txn: txn)
            text?.insert(at: 0, str: "Section", txn: txn)
        }

        try await doc.testReadTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            guard case let .element(heading) = fragment.child(at: 0, txn: txn) else {
                XCTFail("expected element")
                return
            }
            XCTAssertEqual(heading.tag(txn: txn), "heading")
            XCTAssertEqual(heading.getAttr("level", txn: txn), "3")
            XCTAssertNil(heading.getAttr("nonexistent", txn: txn))
        }
    }

    func testRemoveRange() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        try await doc.testWriteTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            fragment.insertElem(at: 0, name: "paragraph", txn: txn)
            fragment.insertElem(at: 1, name: "heading", txn: txn)
            fragment.insertElem(at: 2, name: "bulletList", txn: txn)
            XCTAssertEqual(fragment.childLen(txn: txn), 3)

            fragment.removeRange(at: 0, count: 2, txn: txn)
            XCTAssertEqual(fragment.childLen(txn: txn), 1)

            if case let .element(remaining) = fragment.child(at: 0, txn: txn) {
                XCTAssertEqual(remaining.tag(txn: txn), "bulletList")
            } else {
                XCTFail("expected remaining element")
            }
        }
    }

    func testTextChunksAndString() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        try await doc.testWriteTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            let para = fragment.insertElem(at: 0, name: "paragraph", txn: txn)
            let text = para?.insertText(at: 0, txn: txn)
            text?.insert(at: 0, str: "Chunk text content", txn: txn)
        }

        try await doc.testReadTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            guard case let .element(para) = fragment.child(at: 0, txn: txn) else {
                XCTFail("expected paragraph element")
                return
            }
            guard case let .text(text) = para.child(at: 0, txn: txn) else {
                XCTFail("expected text node")
                return
            }
            XCTAssertEqual(text.string(txn: txn), "Chunk text content")
            XCTAssertGreaterThan(text.length(txn: txn), 0)

            let chunkString = text.withChunks(txn: txn) { chunks in
                chunks.count > 0 ? chunks.string(at: 0) : nil as String?
            } ?? nil
            XCTAssertEqual(chunkString, "Chunk text content")
        }
    }

    func testXmlAttributeIterator() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        try await doc.testWriteTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            let timer = fragment.insertElem(at: 0, name: "timer", txn: txn)
            timer?.insertAttr(key: "data-duration", value: "300", txn: txn)
            timer?.insertAttr(key: "data-type", value: "minutes", txn: txn)
            timer?.insertAttr(key: "data-name", value: "Bake", txn: txn)
        }

        try await doc.testReadTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            guard case let .element(timer) = fragment.child(at: 0, txn: txn) else {
                XCTFail("expected timer element")
                return
            }
            guard let iter = timer.attrIter(txn: txn) else {
                XCTFail("attr iterator should not be nil")
                return
            }
            var attrs: [String: String] = [:]
            for attr in iter {
                attrs[attr.name] = attr.stringValue()
            }
            XCTAssertEqual(attrs["data-duration"], "300")
            XCTAssertEqual(attrs["data-type"], "minutes")
            XCTAssertEqual(attrs["data-name"], "Bake")
            XCTAssertEqual(attrs.count, 3)
        }
    }

    func testPlainTextRoundTrip() async throws {
        let doc = try YrsDocument()
        await doc.ensureRecipeCreateRoots()

        try await doc.testWriteTransaction { _, txn in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return }
            let p1 = fragment.insertElem(at: 0, name: "paragraph", txn: txn)
            let t1 = p1?.insertText(at: 0, txn: txn)
            t1?.insert(at: 0, str: "First paragraph", txn: txn)

            let p2 = fragment.insertElem(at: 1, name: "paragraph", txn: txn)
            let t2 = p2?.insertText(at: 0, txn: txn)
            t2?.insert(at: 0, str: "Second paragraph", txn: txn)
        }

        let plain = try await doc.testReadTransaction { _, txn -> String in
            guard let fragment = doc.xmlFragment(txn: txn, name: "description") else { return "" }
            return XmlFragmentToPlainText.plainText(from: fragment, txn: txn)
        }
        XCTAssertTrue(plain.contains("First paragraph"))
        XCTAssertTrue(plain.contains("Second paragraph"))
    }
}
