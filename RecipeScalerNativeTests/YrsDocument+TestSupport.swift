import Foundation
import RecipeScalerCore
import YrsC
@testable import RecipeScalerNative

extension YrsDocument {
    /// Test entry point for yrs FFI write transactions from the test bundle.
    func testWriteTransaction<T>(
        _ block: (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T
    ) async throws -> T {
        try await withWriteTransaction(block)
    }

    func testReadTransaction<T>(
        _ block: (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T
    ) async throws -> T {
        try await withReadTransaction(block)
    }

    func testEncodeStateAsUpdate() async -> Data? {
        await encodeStateAsUpdate()
    }

    func testApplyDescriptionBlocks(_ blocks: [DescriptionBlock]) async throws {
        try await withWriteTransaction { rawDoc, txn in
            if let fragment = xmlFragment(txn: txn, name: "description") {
                DescriptionXmlFragmentWriter.apply(blocks: blocks, to: fragment, txn: txn)
            }
        }
    }

    func testApplyDescriptionDocument(_ document: RecipeDescriptionDocument) async throws {
        try await withWriteTransaction { rawDoc, txn in
            if let fragment = xmlFragment(txn: txn, name: "description") {
                RecipeDescriptionXmlFragmentWriter.apply(document: document, to: fragment, txn: txn)
            }
        }
    }

    func testSerializedDescriptionHTML() async throws -> String? {
        try await withReadTransaction { _, txn in
            guard let fragment = xmlFragment(txn: txn, name: "description") else { return nil }
            return XmlFragmentToHTML.serializedFragment(from: fragment, txn: txn)
        }
    }
}
