import XCTest
import YrsC
@testable import RecipeScalerNative

/// Tests yrs ↔ yjs roundtrip for the `description` XmlFragment.
///
/// These tests encode state via yrs FFI and write to /tmp for Node.js verification.
/// Run the companion script: `node scripts/test-yjs-description-roundtrip.mjs /tmp/yrs-test-*.bin`
final class YrsDescriptionRoundtripTests: XCTestCase {

    // MARK: - yrs roundtrip (read-what-you-wrote)

    func testDescriptionRoundtripViaYrsState() throws {
        let doc = try YrsDocument()

        // Create description XmlFragment with content via yrs FFI
        try doc.withWriteTransaction { rawDoc, txn in
            let fragment = yxmlfragment(rawDoc, "description")
            XCTAssertNotNil(fragment, "yxmlfragment should return non-nil")

            // Insert a <paragraph> child
            let para = yxmlelem_insert_elem(fragment, txn, 0, "paragraph")
            XCTAssertNotNil(para, "insert paragraph should return non-nil")

            // Insert text into paragraph
            let text = yxmlelem_insert_text(para, txn, 0)
            XCTAssertNotNil(text, "insert text should return non-nil")

            // Write content
            let content = "Привет, мир!"
            content.withCString { cstr in
                yxmltext_insert(text, txn, 0, cstr, nil)
            }
        }

        // Encode state
        guard let state = doc.encodeStateAsUpdate() else {
            XCTFail("encodeStateAsUpdate returned nil")
            return
        }
        XCTAssertGreaterThan(state.count, 0, "State should not be empty")

        // Verify yrs can read back the content
        let html = try doc.withReadTransaction { _, txn in
            XmlFragmentToHTML.serializedFragment(txn: txn)
        }
        XCTAssertNotNil(html, "yrs should read back the description")
        XCTAssertTrue(html?.contains("Привет, мир!") ?? false, "yrs should see the text content")

        // Write to file for Node.js verification
        let path = "/tmp/yrs-test-simple.bin"
        try state.write(to: URL(fileURLWithPath: path))
        print("Wrote \(state.count) bytes to \(path)")
    }

    func testDescriptionWithTimerAndIngredient() throws {
        let doc = try YrsDocument()

        try doc.withWriteTransaction { rawDoc, txn in
            let fragment = yxmlfragment(rawDoc, "description")

            // <paragraph>Step 1: Разогреваем духовку</paragraph>
            let p1 = yxmlelem_insert_elem(fragment, txn, 0, "paragraph")
            let t1 = yxmlelem_insert_text(p1, txn, 0)
            "Step 1: Разогреваем духовку до 200° С.".withCString { cstr in
                yxmltext_insert(t1, txn, 0, cstr, nil)
            }

            // <timer data-timer-id="t1" data-duration="1200" ...>20 минут</timer>
            let timer = yxmlelem_insert_elem(fragment, txn, 1, "timer")
            [("data-timer-id", "t1"), ("data-duration", "1200"),
             ("data-type", "seconds"), ("data-value", "20"),
             ("data-name", "20 минут")].forEach { key, val in
                key.withCString { k in
                    val.withCString { v in
                        var input = YInput()
                        input.tag = Y_JSON_STR
                        input.value.str = v
                        input.len = UInt32(strlen(v))
                        yxmlelem_insert_attr(timer, txn, k, &input)
                    }
                }
            }
            let timerText = yxmlelem_insert_text(timer, txn, 0)
            "20 минут".withCString { cstr in
                yxmltext_insert(timerText, txn, 0, cstr, nil)
            }

            // <ingredient data-ingredient-id="i1" data-name="Сахар">350 г</ingredient>
            let ingr = yxmlelem_insert_elem(fragment, txn, 2, "ingredient")
            [("data-ingredient-id", "i1"), ("data-name", "Сахар")].forEach { key, val in
                key.withCString { k in
                    val.withCString { v in
                        var input = YInput()
                        input.tag = Y_JSON_STR
                        input.value.str = v
                        input.len = UInt32(strlen(v))
                        yxmlelem_insert_attr(ingr, txn, k, &input)
                    }
                }
            }
            let ingrText = yxmlelem_insert_text(ingr, txn, 0)
            "350 г".withCString { cstr in
                yxmltext_insert(ingrText, txn, 0, cstr, nil)
            }
        }

        // Encode state
        guard let state = doc.encodeStateAsUpdate() else {
            XCTFail("encodeStateAsUpdate returned nil")
            return
        }

        // Verify yrs reads it back
        let html = try doc.withReadTransaction { _, txn in
            XmlFragmentToHTML.serializedFragment(txn: txn)
        }
        XCTAssertNotNil(html)
        XCTAssertTrue(html?.contains("Разогреваем") ?? false)
        XCTAssertTrue(html?.contains("timer") ?? false)
        XCTAssertTrue(html?.contains("ingredient") ?? false)

        // Write to file for Node.js
        let path = "/tmp/yrs-test-with-nodes.bin"
        try state.write(to: URL(fileURLWithPath: path))
        print("Wrote \(state.count) bytes to \(path)")

        // Also verify: load state into a new doc → same content
        let doc2 = try YrsDocument(state: state)
        let html2 = try doc2.withReadTransaction { _, txn in
            XmlFragmentToHTML.serializedFragment(txn: txn)
        }
        XCTAssertEqual(html, html2, "yrs roundtrip should preserve content")
    }

    func testDescriptionWithMultipleEdits() throws {
        let doc = try YrsDocument()

        // First edit: add 2 paragraphs
        try doc.withWriteTransaction { rawDoc, txn in
            let fragment = yxmlfragment(rawDoc, "description")
            for i in 0..<2 {
                let p = yxmlelem_insert_elem(fragment, txn, UInt32(i), "paragraph")
                let t = yxmlelem_insert_text(p, txn, 0)
                "Параграф \(i + 1)".withCString { cstr in
                    yxmltext_insert(t, txn, 0, cstr, nil)
                }
            }
        }

        // Second edit: insert more paragraphs (simulates user editing over time)
        try doc.withWriteTransaction { rawDoc, txn in
            guard let fragment = ytype_get(txn, "description") else {
                XCTFail("description fragment not found in txn")
                return
            }
            let count = yxmlelem_child_len(fragment, txn)
            for i in 0..<3 {
                let p = yxmlelem_insert_elem(fragment, txn, count + UInt32(i), "paragraph")
                let t = yxmlelem_insert_text(p, txn, 0)
                "Новый параграф \(i + 1)".withCString { cstr in
                    yxmltext_insert(t, txn, 0, cstr, nil)
                }
            }
        }

        // Encode state (this simulates what the WebView receives)
        guard let state = doc.encodeStateAsUpdate() else {
            XCTFail("encodeStateAsUpdate returned nil")
            return
        }

        // Verify yrs reads all paragraphs
        let html = try doc.withReadTransaction { _, txn in
            XmlFragmentToHTML.serializedFragment(txn: txn)
        }
        XCTAssertTrue(html?.contains("Параграф 1") ?? false)
        XCTAssertTrue(html?.contains("Параграф 2") ?? false)
        XCTAssertTrue(html?.contains("Новый параграф 1") ?? false)

        // Write to file
        let path = "/tmp/yrs-test-multi-edit.bin"
        try state.write(to: URL(fileURLWithPath: path))
        print("Wrote \(state.count) bytes to \(path)")

        // Verify: new doc from state → same content
        let doc2 = try YrsDocument(state: state)
        let html2 = try doc2.withReadTransaction { _, txn in
            XmlFragmentToHTML.serializedFragment(txn: txn)
        }
        XCTAssertEqual(html, html2, "yrs roundtrip after multi-edit should preserve content")
    }

    // MARK: - yrs encode → yjs decode (cross-library roundtrip)

    /// Write the yrs-encoded state to a temp file so the Node.js companion script
    /// can verify that yjs decodes the same `description` XmlFragment.
    func testYrsEncodeYjsDecodeSimpleParagraph() throws {
        let doc = try YrsDocument()

        try doc.withWriteTransaction { rawDoc, txn in
            let fragment = yxmlfragment(rawDoc, "description")
            let p = yxmlelem_insert_elem(fragment, txn, 0, "paragraph")
            let t = yxmlelem_insert_text(p, txn, 0)
            "Hello from yrs!".withCString { cstr in
                yxmltext_insert(t, txn, 0, cstr, nil)
            }
        }

        guard let state = doc.encodeStateAsUpdate() else {
            XCTFail("encodeStateAsUpdate returned nil")
            return
        }

        // yrs roundtrip — must pass (sanity check)
        let html = try doc.withReadTransaction { _, txn in
            XmlFragmentToHTML.serializedFragment(txn: txn)
        }
        XCTAssertNotNil(html, "yrs must read back description")
        XCTAssertTrue(html!.contains("Hello from yrs!"), "yrs must see inserted text")

        // Dump for Node.js verification
        let path = "/tmp/yrs-test-yjs-roundtrip-simple.bin"
        try state.write(to: URL(fileURLWithPath: path))
        print("Cross-lib roundtrip: \(state.count) bytes → \(path)")
    }

    /// Simulate the real-world pattern: multiple edits from different "clients",
    /// then encode and verify both yrs and yjs see the same content.
    func testYrsEncodeYjsDecodeMultiEdit() throws {
        let doc = try YrsDocument()

        // Edit 1: initial content (simulates web Tiptap)
        try doc.withWriteTransaction { rawDoc, txn in
            let fragment = yxmlfragment(rawDoc, "description")
            // paragraph 1
            let p1 = yxmlelem_insert_elem(fragment, txn, 0, "paragraph")
            let t1 = yxmlelem_insert_text(p1, txn, 0)
            "Step 1: Preheat oven.".withCString { cstr in
                yxmltext_insert(t1, txn, 0, cstr, nil)
            }
        }

        // Edit 2: add ordered list (simulates subsequent editing)
        try doc.withWriteTransaction { rawDoc, txn in
            guard let fragment = ytype_get(txn, "description") else { return }
            let ol = yxmlelem_insert_elem(fragment, txn, 1, "orderedList")
            let li = yxmlelem_insert_elem(ol, txn, 0, "listItem")
            let p = yxmlelem_insert_elem(li, txn, 0, "paragraph")
            let t = yxmlelem_insert_text(p, txn, 0)
            "Mix sugar and cream cheese.".withCString { cstr in
                yxmltext_insert(t, txn, 0, cstr, nil)
            }
        }

        guard let state = doc.encodeStateAsUpdate() else {
            XCTFail("encodeStateAsUpdate returned nil")
            return
        }

        // Verify yrs reads back
        let html = try doc.withReadTransaction { _, txn in
            XmlFragmentToHTML.serializedFragment(txn: txn)
        }
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("Preheat oven"))
        XCTAssertTrue(html!.contains("Mix sugar"))

        let path = "/tmp/yrs-test-yjs-roundtrip-multi.bin"
        try state.write(to: URL(fileURLWithPath: path))
        print("Multi-edit roundtrip: \(state.count) bytes → \(path)")
    }

    // MARK: - Real API state

    func testRealApiStateReadableByYrs() throws {
        let apiStatePath = "/tmp/cheesecake-yjs.bin"
        guard FileManager.default.fileExists(atPath: apiStatePath) else {
            throw XCTSkip("No API state file at \(apiStatePath). Download it first.")
        }

        let state = try Data(contentsOf: URL(fileURLWithPath: apiStatePath))
        let doc = try YrsDocument(state: state)

        let html = try doc.withReadTransaction { _, txn in
            XmlFragmentToHTML.serializedFragment(txn: txn)
        }
        XCTAssertNotNil(html, "yrs must read description from real API state")
        XCTAssertGreaterThan(html!.count, 100, "description should have substantial content")
        print("yrs reads description HTML: \(html!.prefix(200))")

        // Re-encode and write for Node.js verification
        guard let reEncoded = doc.encodeStateAsUpdate() else {
            XCTFail("encodeStateAsUpdate returned nil")
            return
        }
        let path = "/tmp/yrs-test-real-api-reencoded.bin"
        try reEncoded.write(to: URL(fileURLWithPath: path))
        print("Re-encoded API state: \(reEncoded.count) bytes → \(path)")
    }
}
