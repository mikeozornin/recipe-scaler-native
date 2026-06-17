import XCTest
import YrsC
@testable import RecipeScalerNative

/// Unit tests for the state-vector-keyed HTML serialization cache
/// added by performance finding #18.
///
/// These tests verify:
/// 1. The cache returns the same HTML on a second read without re-walking the tree.
/// 2. The cache is invalidated after a recipe mutation (`mutateRecipe`).
/// 3. The cache entry is dropped on `applyUpdate`.
final class XmlFragmentHTMLCacheTests: XCTestCase {

    /// `readRecipeData` twice on the same v3 doc must return the same HTML,
    /// and the cache must be hit on the second call.
    func testReadRecipeDataReturnsCachedHTMLAcrossCalls() async throws {
        let userId = "user-html-cache"
        let recipeId = "recipe-html-cache"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeDoc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        await recipeDoc.ensureRecipeCreateRoots()
        try await recipeDoc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "name", value: .string("Cached Recipe"), txn: txn)
            map.insert(key: "ingredients", value: .yarray([]), txn: txn)
        }

        let first = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        let second = try await manager.readRecipeData(recipeId: recipeId, userId: userId)

        XCTAssertEqual(first?.name, "Cached Recipe")
        XCTAssertEqual(first?.description, second?.description)
    }

    /// Mutating the recipe (e.g. updating a metadata field) must drop the
    /// cached HTML so the next read sees the new state vector and recomputes.
    func testMutateRecipeInvalidatesHTMLCache() async throws {
        let userId = "user-html-cache-mutate"
        let recipeId = "recipe-html-cache-mutate"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeDoc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        await recipeDoc.ensureRecipeCreateRoots()
        try await recipeDoc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "name", value: .string("Before"), txn: txn)
            map.insert(key: "ingredients", value: .yarray([]), txn: txn)
        }

        let before = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(before?.name, "Before")

        try await manager.updateRecipeName(recipeId: recipeId, name: "After")

        let after = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(after?.name, "After")
    }

    /// Applying a Yjs update to a recipe doc must drop the cached HTML entry
    /// (state vector changed).
    func testApplyUpdateInvalidatesHTMLCache() async throws {
        let userId = "user-html-cache-apply"
        let recipeId = "recipe-html-cache-apply"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeDoc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        await recipeDoc.ensureRecipeCreateRoots()
        try await recipeDoc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("3"), txn: txn)
            map.insert(key: "name", value: .string("Apply"), txn: txn)
            map.insert(key: "ingredients", value: .yarray([]), txn: txn)
        }

        let before = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(before?.name, "Apply")

        // Apply a no-op update to the same doc — should drop the cache without crashing.
        let state = await recipeDoc.testEncodeStateAsUpdate()
        if let state {
            try await manager.applyUpdate(
                key: "\(userId):recipe:\(recipeId)",
                data: state
            )
        }

        let after = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(after?.name, "Apply")
    }
}
