//
//  ThirdPartyRecipeImportService.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

@MainActor
final class ThirdPartyRecipeImportService {
    private let syncService: YjsSyncService

    init(syncService: YjsSyncService) {
        self.syncService = syncService
    }

    func importFile(
        url: URL,
        isOnline: Bool,
        progress: @escaping (_ completed: Int, _ total: Int) -> Void
    ) async throws -> ThirdPartyImportResult {
        // Security scope MUST wrap ALL file I/O (detect + enumerate + extract).
        // Without this, on physical device with files from "Files (On My iPhone)",
        // reading a security-scoped URL outside picker scope fails with permission
        // error — which the upper catch converts into "unsupportedFormat".
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let format = try ThirdPartyFormatDetector.detect(url: url)
        guard format != .unsupported else {
            throw ThirdPartyImportError.unsupportedFormat
        }

        let entries = try ThirdPartyFormatDetector.enumerateRecipeEntries(url: url, format: format)
        guard !entries.isEmpty else {
            throw ThirdPartyImportError.emptyArchive
        }
        try ThirdPartyFormatDetector.validateEntryCount(entries)

        var importedRecipeIds: [String] = []
        var failed: [(fileName: String, error: ThirdPartyImportError)] = []
        var photosSkippedOffline = 0
        var photosFailed = 0
        let total = entries.count

        for (index, entry) in entries.enumerated() {
            if Task.isCancelled {
                break
            }

            do {
                let draft = try parseEntry(entry, format: format)
                let recipeId = try await syncService.applyImportedRecipe(draft)
                importedRecipeIds.append(recipeId)

                if let imageData = draft.imageData {
                    if isOnline {
                        do {
                            try await syncService.uploadImportedRecipeImage(
                                recipeId: recipeId,
                                imageData: imageData
                            )
                        } catch {
                            photosFailed += 1
                        }
                    } else {
                        photosSkippedOffline += 1
                    }
                }

                // US8: map Paprika `categories` / Crouton `tags` → recipe folders.
                // Failures here are non-fatal: recipe is already imported, so we
                // swallow folder resolution errors and keep the import moving.
                if !draft.categoryLabels.isEmpty {
                    try? await syncService.applyCategoryLabelsToRecipe(
                        recipeId: recipeId,
                        labels: draft.categoryLabels
                    )
                }
            } catch let error as ThirdPartyImportError {
                failed.append((entry.fileName, error))
            } catch {
                failed.append((entry.fileName, .corruptEntry(fileName: entry.fileName)))
            }

            progress(index + 1, total)
        }

        return ThirdPartyImportResult(
            importedRecipeIds: importedRecipeIds,
            failed: failed,
            photosSkippedOffline: photosSkippedOffline,
            photosFailed: photosFailed
        )
    }

    private func parseEntry(
        _ entry: ThirdPartyArchiveEntry,
        format: ThirdPartyFormat
    ) throws -> ThirdPartyRecipeDraft {
        switch format {
        case .paprikaArchive, .paprikaSingle:
            return try PaprikaRecipeParser.parse(
                gzipData: entry.data,
                fileName: entry.fileName,
                sourceFormat: format
            )
        case .croutonArchive, .croutonSingle:
            return try CroutonRecipeParser.parse(
                jsonData: entry.data,
                fileName: entry.fileName,
                sourceFormat: format
            )
        case .unsupported:
            throw ThirdPartyImportError.unsupportedFormat
        }
    }
}

enum ThirdPartyImportErrorLocalizer {
    static func localize(_ error: ThirdPartyImportError) -> String {
        switch error {
        case .unsupportedFormat:
            return Bundle.currentLocalizedString("import.third-party-unsupported")
        case .emptyArchive:
            return Bundle.currentLocalizedString("import.third-party-empty")
        case let .recipeLimitExceeded(limit):
            let template = Bundle.currentLocalizedString("import.third-party-limit")
            return String(format: template, locale: AppLanguagePreference.current.locale, limit)
        case .corruptEntry, .invalidJSON, .gzipFailed:
            return Bundle.currentLocalizedString("import.third-party-unsupported")
        }
    }

    static func summaryMessage(for result: ThirdPartyImportResult) -> String {
        let template = Bundle.currentLocalizedString("import.third-party-summary")
        let imported = result.importedRecipeIds.count
        let failedCount = result.failed.count
        return String(format: template, locale: AppLanguagePreference.current.locale, imported, failedCount)
    }

    static func photoWarningMessage(for result: ThirdPartyImportResult) -> String? {
        if result.photosSkippedOffline > 0 {
            let template = Bundle.currentLocalizedString("import.third-party-photo-skipped-offline")
            return String(
                format: template,
                locale: AppLanguagePreference.current.locale,
                result.photosSkippedOffline
            )
        }
        if result.photosFailed > 0 {
            let template = Bundle.currentLocalizedString("import.third-party-photo-failed")
            return String(
                format: template,
                locale: AppLanguagePreference.current.locale,
                result.photosFailed
            )
        }
        return nil
    }

    static func progressMessage(completed: Int, total: Int) -> String {
        let template = Bundle.currentLocalizedString("import.third-party-progress")
        return String(format: template, locale: AppLanguagePreference.current.locale, completed, total)
    }

    static func localizedFailure(fileName: String, error: ThirdPartyImportError) -> String {
        let template = Bundle.currentLocalizedString("account.data.import.recipe-failed %@ %@")
        let reason = localize(error)
        return String(
            format: template,
            locale: AppLanguagePreference.current.locale,
            fileName,
            reason
        )
    }
}
