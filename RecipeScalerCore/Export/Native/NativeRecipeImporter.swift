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

        let recipesData: Data
        do {
            var buffer = Data()
            try _ = archive.extract(recipesEntry) { chunk in
                buffer.append(chunk)
            }
            recipesData = buffer
        } catch {
            throw NativeImportError.invalidJSON(error.localizedDescription)
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

        // 3. Extract images
        var imageEntries: [ImageEntry] = []
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

            var imageData = Data()
            try? _ = archive.extract(entry) { chunk in
                imageData.append(chunk)
            }

            if !imageData.isEmpty {
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
