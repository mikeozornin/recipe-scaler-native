import Foundation
import YrsC

#if DEBUG
extension YrsDocument {
    /// Cross-module test entry point. Actor methods whose closure parameters are non-Sendable
    /// (yrs FFI pointers) are not visible to the test bundle; these wrappers stay in the app target.
    func testWriteTransaction<T>(
        _ block: @Sendable (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T
    ) async throws -> T {
        try withWriteTransaction(block)
    }

    func testReadTransaction<T>(
        _ block: @Sendable (UnsafeMutablePointer<YDoc>, OpaquePointer) throws -> T
    ) async throws -> T {
        try withReadTransaction(block)
    }

    func testEncodeStateAsUpdate() async -> Data? {
        encodeStateAsUpdate()
    }
}
#endif
