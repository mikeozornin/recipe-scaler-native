import Foundation
import ZIPFoundation

/// Import a Recipe Scaler export file (JSON or ZIP, v1.0–v1.4).
///
/// Returns parsed recipes, folders, and image entries ready to be
/// applied to Y.Doc by `NativeExportImportService`.
public enum NativeRecipeImporter {

    /// Result of parsing an export file.
    public struct ParsedImport: Sendable {
        public let version: NativeFormatVersion
        public let recipes: [NativeRecipe]
        public let folders: [NativeFolder]
        public let imageEntries: [ImageEntry]

        public init(
            version: NativeFormatVersion,
            recipes: [NativeRecipe],
            folders: [NativeFolder],
            imageEntries: [ImageEntry]
        ) {
            self.version = version
            self.recipes = recipes
            self.folders = folders
            self.imageEntries = imageEntries
        }
    }

    /// An image file extracted from a ZIP archive.
    public struct ImageEntry: Sendable {
        public let recipeId: String
        public let kind: ImageKind
        public let data: Data
        public let relativePath: String

        public enum ImageKind: String, Sendable {
            case full
            case preview
        }
    }

    /// Parse and validate a Recipe Scaler export file.
    ///
    /// - Parameter url: File URL to a `.json` or `.zip` export.
    /// - Returns: A `ParsedImport` with recipes, folders, and image data.
    public static func parse(url: URL) throws -> ParsedImport {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let isZip = url.pathExtension.lowercased() == "zip"

        if isZip {
            return try parseZip(url: url)
        } else {
            return try parseJSON(url: url)
        }
    }

    // MARK: - Private

    private static func parseJSON(url: URL) throws -> ParsedImport {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw NativeImportError.fileAccessFailed
        }

        // #32: pre-flight JSON byte cap — defense-in-depth against CPU/memory bombs.
        guard data.count <= ThirdPartyImportLimits.maxRecipeJSONBytes else {
            throw NativeImportError.jsonSizeLimitExceeded
        }

        let payload: NativeExportPayload
        do {
            payload = try JSONDecoder().decode(NativeExportPayload.self, from: data)
        } catch {
            throw NativeImportError.invalidJSON(error.localizedDescription)
        }

        let version = normalizeNativeFormatVersion(
            version: payload.metadata.version,
            type: payload.metadata.type
        )

        // Validate
        let validation = NativeFormatValidator.validate(payload: payload, version: version)
        if !validation.isValid {
            throw NativeImportError.validationFailed(validation.structuralErrors)
        }

        return ParsedImport(
            version: version,
            recipes: payload.recipes,
            folders: payload.folders ?? [],
            imageEntries: []
        )
    }

    private static func parseZip(url: URL) throws -> ParsedImport {
        let archive = try Archive(url: url, accessMode: .read)

        // 1. Read recipes.json
        guard let recipesEntry = archive["recipes.json"] ?? archive["export.json"] else {
            throw NativeImportError.missingRecipesJson
        }

        let maxArchiveBytes = ThirdPartyImportLimits.maxDecompressedArchiveBytes

        // Triple-guard (B1+B2+B3) for `recipes.json`: per-entry cap = maxRecipeJSONBytes.
        // B1: pre-flight on central-directory declared size.
        guard recipesEntry.uncompressedSize <= ThirdPartyImportLimits.maxRecipeJSONBytes else {
            throw NativeImportError.entrySizeLimitExceeded(entryPath: recipesEntry.path)
        }

        let recipesData: Data
        do {
            var buffer = Data()
            var entryRunning = 0
            var streamingOverflow: NativeImportError?
            _ = try archive.extract(recipesEntry) { chunk in
                entryRunning += chunk.count
                if entryRunning > ThirdPartyImportLimits.maxRecipeJSONBytes {
                    streamingOverflow = .entrySizeLimitExceeded(entryPath: recipesEntry.path)
                    return
                }
                buffer.append(chunk)
            }
            if let overflow = streamingOverflow {
                throw overflow
            }
            recipesData = buffer
        } catch let error as NativeImportError {
            throw error
        } catch {
            throw NativeImportError.invalidJSON(error.localizedDescription)
        }

        // #32: pre-flight JSON byte cap.
        guard recipesData.count <= ThirdPartyImportLimits.maxRecipeJSONBytes else {
            throw NativeImportError.jsonSizeLimitExceeded
        }

        let payload: NativeExportPayload
        do {
            payload = try JSONDecoder().decode(NativeExportPayload.self, from: recipesData)
        } catch {
            throw NativeImportError.invalidJSON(error.localizedDescription)
        }

        let version = normalizeNativeFormatVersion(
            version: payload.metadata.version,
            type: payload.metadata.type
        )

        // 2. Validate
        let validation = NativeFormatValidator.validate(payload: payload, version: version)
        if !validation.isValid {
            throw NativeImportError.validationFailed(validation.structuralErrors)
        }

        // 3. Extract images with per-entry (maxImageBytes) + aggregate (maxArchiveBytes) cap.
        var imageEntries: [ImageEntry] = []
        var archiveRunningTotal = recipesData.count

        for entry in archive {
            let path = entry.path
            // Match images/<recipeId>/full.webp or images/<recipeId>/preview.webp
            let components = path.components(separatedBy: "/")
            guard components.count == 3,
                  components[0] == "images",
                  let fileName = components.last,
                  let ext = fileName.split(separator: ".").last,
                  ext.lowercased() == "webp" else {
                continue
            }

            let recipeId = components[1]
            let kind: ImageEntry.ImageKind
            if fileName == "full.webp" {
                kind = .full
            } else if fileName == "preview.webp" {
                kind = .preview
            } else {
                continue
            }

            // B1+B3 pre-flight on declared sizes.
            guard entry.uncompressedSize <= ThirdPartyImportLimits.maxImageBytes else {
                throw NativeImportError.entrySizeLimitExceeded(entryPath: path)
            }
            if archiveRunningTotal + Int(entry.uncompressedSize) > maxArchiveBytes {
                throw NativeImportError.archiveSizeLimitExceeded
            }

            // B2 streaming running total — catches spoofed central directories.
            var imageData = Data()
            var entryRunning = 0
            var streamingOverflow: NativeImportError?
            do {
                _ = try archive.extract(entry) { chunk in
                    entryRunning += chunk.count
                    if entryRunning > ThirdPartyImportLimits.maxImageBytes {
                        streamingOverflow = .entrySizeLimitExceeded(entryPath: path)
                        return
                    }
                    if archiveRunningTotal + entryRunning > maxArchiveBytes {
                        streamingOverflow = .archiveSizeLimitExceeded
                        return
                    }
                    imageData.append(chunk)
                }
            } catch {
                // Treat extraction errors as a missing image (legacy behaviour).
                continue
            }
            if let overflow = streamingOverflow {
                throw overflow
            }

            if !imageData.isEmpty {
                archiveRunningTotal += imageData.count
                imageEntries.append(ImageEntry(
                    recipeId: recipeId,
                    kind: kind,
                    data: imageData,
                    relativePath: path
                ))
            }
        }

        return ParsedImport(
            version: version,
            recipes: payload.recipes,
            folders: payload.folders ?? [],
            imageEntries: imageEntries
        )
    }
}
