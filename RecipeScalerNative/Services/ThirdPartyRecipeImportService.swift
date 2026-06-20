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

        // Cheap central-directory read: archive entry count (no decompression).
        // Used for progress denominator only — actual extraction limit is enforced
        // inside the stream (recipeLimitExceeded as soon as count > max).
        let total: Int
        if format == .paprikaArchive || format == .croutonArchive {
            total = ThirdPartyFormatDetector.estimatedRecipeCount(url: url, format: format) ?? 0
        } else {
            // Single-file import: exactly one recipe.
            total = 1
        }

        guard total > 0 else {
            throw ThirdPartyImportError.emptyArchive
        }

        var importedRecipeIds: [String] = []
        var failed: [(fileName: String, error: ThirdPartyImportError)] = []
        var photosSkippedOffline = 0
        var photosFailed = 0
        var photosOversized = 0

        let stream = ThirdPartyFormatDetector.enumerateRecipeEntriesStream(
            url: url,
            format: format,
            maxEntryBytes: ThirdPartyImportLimits.maxDecompressedEntryBytes,
            maxArchiveBytes: ThirdPartyImportLimits.maxDecompressedArchiveBytes
        )
        var index = 0
        for try await entry in stream {
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
                } else if draft.imageOversized {
                    // MIK-119 [review #35]: photo was present in the source but
                    // exceeded the size cap — surface a dedicated counter so the
                    // import summary can warn the user instead of dropping silently.
                    photosOversized += 1
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

            index += 1
            progress(index, total)
        }

        return ThirdPartyImportResult(
            importedRecipeIds: importedRecipeIds,
            failed: failed,
            photosSkippedOffline: photosSkippedOffline,
            photosFailed: photosFailed,
            photosOversized: photosOversized
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
        case .entrySizeLimitExceeded:
            return Bundle.currentLocalizedString("import.third-party-entry-too-large")
        case .archiveSizeLimitExceeded:
            return Bundle.currentLocalizedString("import.third-party-archive-too-large")
        case .jsonSizeLimitExceeded:
            return Bundle.currentLocalizedString("import.third-party-json-too-large")
        }
    }

    static func summaryMessage(for result: ThirdPartyImportResult) -> String {
        let template = Bundle.currentLocalizedString("import.third-party-summary")
        let imported = result.importedRecipeIds.count
        let failedCount = result.failed.count
        return String(format: template, locale: AppLanguagePreference.current.locale, imported, failedCount)
    }

    static func photoWarningMessage(for result: ThirdPartyImportResult) -> String? {
        // MIK-119 [review #35]: surface all photo warnings (oversized + offline
        // + failed), not just the first one. Joined with newlines so the import
        // summary is honest about every dropped photo bucket.
        var messages: [String] = []
        if result.photosOversized > 0 {
            let template = Bundle.currentLocalizedString("import.third-party-photo-oversized")
            messages.append(
                String(
                    format: template,
                    locale: AppLanguagePreference.current.locale,
                    result.photosOversized
                )
            )
        }
        if result.photosSkippedOffline > 0 {
            let template = Bundle.currentLocalizedString("import.third-party-photo-skipped-offline")
            messages.append(
                String(
                    format: template,
                    locale: AppLanguagePreference.current.locale,
                    result.photosSkippedOffline
                )
            )
        }
        if result.photosFailed > 0 {
            let template = Bundle.currentLocalizedString("import.third-party-photo-failed")
            messages.append(
                String(
                    format: template,
                    locale: AppLanguagePreference.current.locale,
                    result.photosFailed
                )
            )
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
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
