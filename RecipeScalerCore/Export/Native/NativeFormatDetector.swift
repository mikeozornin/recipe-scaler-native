#if !os(watchOS)
import Foundation
import ZIPFoundation

/// Detect the Recipe Scaler export format version from a file URL.
public enum NativeFormatDetector {

    /// Detect the export format version from a JSON or ZIP file.
    /// Returns the normalized version. Throws if the file is not a valid Recipe Scaler export.
    public static func detect(url: URL) throws -> NativeFormatVersion {
        let data: Data
        if isZipExtension(url.pathExtension) {
            data = try readRecipesJsonFromZip(url: url)
        } else {
            data = try Data(contentsOf: url)
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let json = jsonObject as? [String: Any] else {
                throw NativeImportError.invalidJSON("Root JSON is not an object")
            }
            guard let metadata = json["metadata"] as? [String: Any] else {
                // No metadata at all — legacy v1.0 format
                return .v1_0
            }
            let version = metadata["version"] as? String
            let type = metadata["type"] as? String
            return normalizeNativeFormatVersion(version: version, type: type)
        } catch let error as NativeImportError {
            throw error
        } catch {
            throw NativeImportError.invalidJSON(error.localizedDescription)
        }
    }

    /// Read `recipes.json` from inside a ZIP archive.
    private static func readRecipesJsonFromZip(url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let archive = try Archive(url: url, accessMode: .read)

        guard let entry = archive["recipes.json"] ?? archive["export.json"] else {
            throw NativeImportError.missingRecipesJson
        }

        var data = Data()
        try _ = archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    /// Returns `true` for file extensions that wrap a ZIP archive of the
    /// Recipe Scaler v1.4 format.
    ///
    /// - `.zip` — bulk export (multiple recipes + images), supported since v1.0.
    /// - `.recipe` — single-recipe AirDrop payload (spec 057); same ZIP layout
    ///   with `recipes.json` at the root.
    private static func isZipExtension(_ pathExtension: String) -> Bool {
        let lower = pathExtension.lowercased()
        return lower == "zip" || lower == "recipe"
    }
}
#endif
