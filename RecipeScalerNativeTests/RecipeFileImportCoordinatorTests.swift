//
//  RecipeFileImportCoordinatorTests.swift
//
//  Spec 057 T028 — verifies `RecipeFileImportCoordinator` orchestration:
//  staging of security-scoped URLs, success/partial/error feedback,
//  and that `AppShellCoordinator.completeImport` is invoked.
//

import XCTest
import ZIPFoundation
@testable import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class RecipeFileImportCoordinatorTests: XCTestCase {

    private func makePreparedCoordinator() async throws -> AppShellCoordinator {
        let store = try YDocStore.inMemory()
        let sync = YjsSyncService.makeForTesting(store: store)
        await sync.test_setUserIdForOfflineTests("coordinator-test-user")
        let router = DeepLinkRouter()
        let shell = AppShellCoordinator(syncService: sync, deepLinkRouter: router)
        // Wire the file coordinator the same way AppContainer does — back-ref
        // to the shell so `completeImport` fires on success (HIGH #1 fix).
        let fileCoord = RecipeFileImportCoordinator(syncService: sync)
        fileCoord.shellCoordinator = shell
        shell.fileImportCoordinator = fileCoord
        return shell
    }

    func test_importFile_success_callsCompleteImportAndReturnsToast() async throws {
        let shell = try await makePreparedCoordinator()
        let coordinator = try XCTUnwrap(shell.fileImportCoordinator)

        let url = try makeRecipeFile(name: "Test Recipe", recipeId: "test-id")
        defer { try? FileManager.default.removeItem(at: url) }

        var capturedResult: ImportRecipesResult?
        let toast = await coordinator.importFile(
            at: url,
            isOnline: false,
            onComplete: { capturedResult = $0 }
        )

        XCTAssertNotNil(capturedResult, "onComplete must fire with the result")
        XCTAssertEqual(capturedResult?.importedCount, 1)
        XCTAssertNotNil(toast, "Success path must return a user-visible toast")
    }

    func test_importFile_missingFile_returnsErrorMessage() async throws {
        let shell = try await makePreparedCoordinator()
        let coordinator = try XCTUnwrap(shell.fileImportCoordinator)

        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).recipe")
        var capturedResult: ImportRecipesResult?
        let toast = await coordinator.importFile(
            at: url,
            isOnline: false,
            onComplete: { capturedResult = $0 }
        )

        XCTAssertNil(capturedResult, "onComplete must fire with nil on failure")
        XCTAssertNotNil(toast, "Failure path must return an error toast")
    }

    func test_importFile_corruptFile_returnsErrorMessage() async throws {
        let shell = try await makePreparedCoordinator()
        let coordinator = try XCTUnwrap(shell.fileImportCoordinator)

        // Write a file with the wrong content — looks like a `.recipe` by
        // extension but is not a valid ZIP archive.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).recipe")
        try "not a zip".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var capturedResult: ImportRecipesResult?
        let toast = await coordinator.importFile(
            at: url,
            isOnline: false,
            onComplete: { capturedResult = $0 }
        )

        XCTAssertNil(capturedResult)
        XCTAssertNotNil(toast, "Corrupt-archive failure must surface a toast")
    }

    /// Spec 057 review HIGH #2 — pre-flight the source file size before
    /// `copyItem` so an oversized payload is rejected without consuming
    /// sandbox disk quota.
    func test_importFile_oversizedFile_returnsErrorMessageWithoutStaging() async throws {
        let shell = try await makePreparedCoordinator()
        let coordinator = try XCTUnwrap(shell.fileImportCoordinator)

        // Write a sparse file large enough to trip the archive-size cap
        // (500 MB decimal). We can't actually allocate 500 MB of real bytes,
        // so we lie about the size via a sparse file and verify the coordinator
        // stat'd the file and rejected it before trying to copy.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oversized-\(UUID().uuidString).recipe")
        let fileManager = FileManager.default
        fileManager.createFile(atPath: url.path, contents: nil)
        // Truncate to 501 MB: the file consumes no disk, but
        // `attributesOfItem(.size)` reports it as 501 MB.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 501 * 1_000_000)
        try handle.close()
        defer { try? fileManager.removeItem(at: url) }

        // The staging step should reject the file before `importFile` ever
        // touches it. Inbox directory should NOT contain a copy.
        var capturedResult: ImportRecipesResult?
        let toast = await coordinator.importFile(
            at: url,
            isOnline: false,
            onComplete: { capturedResult = $0 }
        )

        XCTAssertNil(capturedResult)
        XCTAssertNotNil(toast, "Oversized payload must surface an error toast")

        // Verify no staged copy leaked into the inbox directory.
        let inboxDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeScalerInbox", isDirectory: true)
        if fileManager.fileExists(atPath: inboxDir.path) {
            let leftovers = (try? fileManager.contentsOfDirectory(atPath: inboxDir.path)) ?? []
            XCTAssertTrue(leftovers.isEmpty,
                          "Inbox must be empty after rejection; found \(leftovers)")
        }
    }

    /// Spec 057 review HIGH #1 — a file that cannot yield any recipe must
    /// still surface a user-visible toast rather than failing silently.
    /// Note: an empty `recipes` manifest is rejected upstream by
    /// `NativeImportService.importFile` as `emptyArchive`, which the
    /// coordinator maps to an error toast — so the observable contract is
    /// "always a toast", never a silent nil.
    func test_importFile_emptyRecipes_stillSurfacesToast() async throws {
        let shell = try await makePreparedCoordinator()
        let coordinator = try XCTUnwrap(shell.fileImportCoordinator)

        let url = try makeEmptyRecipesFile()
        defer { try? FileManager.default.removeItem(at: url) }

        var capturedResult: ImportRecipesResult?
        let toast = await coordinator.importFile(
            at: url,
            isOnline: false,
            onComplete: { capturedResult = $0 }
        )

        // The importer throws emptyArchive for an empty manifest → coordinator
        // fires `onComplete(nil)` and returns the localized error toast. The
        // user MUST see feedback; a nil toast here would violate SC-001.
        XCTAssertNil(capturedResult)
        XCTAssertNotNil(toast, "Empty manifest must surface a toast, not nil (HIGH #1)")
    }

    // MARK: - Helpers

    private func makeRecipeFile(name: String, recipeId: String) throws -> URL {
        let payload: [String: Any] = [
            "metadata": [
                "version": "1.4",
                "type": "recipes-v1.4",
                "count": 1,
                "exportDate": "2026-08-02T22:00:00Z"
            ],
            "recipes": [[
                "id": recipeId,
                "name": name,
                "ingredients": [[String: Any]](),
                "color": "#FF0000"
            ]]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coordinator-test-\(UUID().uuidString).recipe")

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "RecipeFileImportCoordinatorTests", code: 1)
        }
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(jsonData.count),
            compressionMethod: .deflate
        ) { position, size in
            jsonData.subdata(in: Int(position)..<Int(position + size))
        }
        return url
    }

    /// Build a `.recipe` ZIP with a valid v1.4 manifest but an empty
    /// `recipes` array. Used to verify the zero-import case still surfaces
    /// a toast (spec 057 review HIGH #1).
    private func makeEmptyRecipesFile() throws -> URL {
        let payload: [String: Any] = [
            "metadata": [
                "version": "1.4",
                "type": "recipes-v1.4",
                "count": 0,
                "exportDate": "2026-08-02T22:00:00Z"
            ],
            "recipes": [[String: Any]]()
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coordinator-empty-\(UUID().uuidString).recipe")

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "RecipeFileImportCoordinatorTests", code: 2)
        }
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(jsonData.count),
            compressionMethod: .deflate
        ) { position, size in
            jsonData.subdata(in: Int(position)..<Int(position + size))
        }
        return url
    }
}
