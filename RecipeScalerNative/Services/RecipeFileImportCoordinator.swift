//
//  RecipeFileImportCoordinator.swift
//  RecipeScalerNative
//
//  Spec 057 — orchestrates the silent import of an incoming `.recipe` file
//  received via AirDrop / Files / Mail.
//
//  The coordinator:
//  1. Pre-flights the source file size to reject oversized payloads before
//     any bytes are copied (disk-fill / local-DoS defense — spec 057 review).
//  2. Copies the security-scoped Inbox URL into a stable `tmp` location
//     (iOS reclaims Inbox aggressively; ZIP readers like `Archive` may need
//     multiple passes over the file, so we work off a copy).
//  3. Invokes `NativeExportImportService.importFile(url:...)` which parses
//     the v1.4 ZIP, applies recipes/folders/images to Y.Doc, and returns
//     a `NativeImportResult`.
//  4. Wraps the result as an `ImportRecipesResult` and hands it to the
//     `AppShellCoordinator.completeImport` flow — same path the manual
//     `ImportRecipeSheet` uses — so the user gets the standard toast and
//     auto-navigation to the imported recipe.
//  5. Always surfaces a user-visible toast: success, no-recipes-applied
//     warning, or error message (spec SC-001).
//
//  Future-proof: this same coordinator can drive Universal Links and
//  push-notification attachments later, not just AirDrop.
//

import Foundation
import RecipeScalerCore

@MainActor
final class RecipeFileImportCoordinator {
    private let syncService: YjsSyncService
    private let exportImportService: NativeExportImportService

    /// Injected so tests can verify the success toast without going through
    /// `AppShellCoordinator.completeImport`. Real app passes the coordinator.
    weak var shellCoordinator: AppShellCoordinator?

    init(syncService: YjsSyncService) {
        self.syncService = syncService
        self.exportImportService = NativeExportImportService(syncService: syncService)
    }

    /// Import the file at `url` silently. Returns the user-facing toast
    /// message (already localized) or `nil` if the caller will handle
    /// feedback itself (e.g. via `AppShellCoordinator.completeImport`).
    @discardableResult
    func importFile(
        at url: URL,
        isOnline: Bool,
        onComplete: ((ImportRecipesResult?) -> Void)? = nil
    ) async -> String? {
        let stagedURL: URL
        do {
            stagedURL = try stageSecurityScopedFile(url)
        } catch {
            let message = UserFacingAPIError.message(for: error)
            onComplete?(nil)
            return message
        }

        var importedResult: ImportRecipesResult?
        var failureMessage: String?
        do {
            let result = try await exportImportService.importFile(
                url: stagedURL,
                isOnline: isOnline,
                progress: { _, _ in }
            )
            importedResult = ImportRecipesResult(
                recipeIds: result.importedRecipeIds,
                importedCount: result.importedCount
            )
        } catch {
            failureMessage = UserFacingAPIError.message(for: error)
        }

        try? FileManager.default.removeItem(at: stagedURL)

        if let result = importedResult {
            // Spec 057 review HIGH #1: never silently swallow the case where
            // the archive parsed but zero recipes applied (e.g. all rejected
            // by limits or validation). Surface a warning toast instead.
            if result.importedCount > 0, let shellCoordinator {
                let toast = shellCoordinator.completeImport(result)
                onComplete?(result)
                return toast
            }
            onComplete?(result)
            return String(localized: "import.no-recipes-applied")
        }

        onComplete?(nil)
        return failureMessage
    }

    /// Copy the security-scoped source URL into `tmp/RecipeScalerInbox/`
    /// so the importer can read it freely. Returns the new URL.
    ///
    /// `startAccessingSecurityScopedResource()` is required for URLs coming
    /// from AirDrop/Files/Mail — without it the read fails with EPERM.
    ///
    /// Spec 057 review HIGH #2: the source file is stat'td before `copyItem`
    /// so an oversized payload (crafted AirDrop, accidental disk-fill) is
    /// rejected before consuming sandbox disk quota. The cap matches the
    /// importer's aggregate archive limit — a compressed `.recipe` larger
    /// than that cannot possibly decode to a valid recipe payload.
    private func stageSecurityScopedFile(_ source: URL) throws -> URL {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let sourceSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let sizeLimit = Int64(ThirdPartyImportLimits.maxDecompressedArchiveBytes)
        guard sourceSize <= sizeLimit else {
            throw NativeImportError.archiveSizeLimitExceeded
        }

        let inboxDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeScalerInbox", isDirectory: true)
        try FileManager.default.createDirectory(
            at: inboxDir,
            withIntermediateDirectories: true
        )

        // Preserve the original extension so the importer can route by type.
        let ext = source.pathExtension.isEmpty ? "recipe" : source.pathExtension
        let destination = inboxDir.appendingPathComponent(
            "incoming-\(UUID().uuidString).\(ext)"
        )

        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            // If `copyItem` created a partial file before failing, clean it
            // up so we don't leak bytes into the sandbox.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }
}
