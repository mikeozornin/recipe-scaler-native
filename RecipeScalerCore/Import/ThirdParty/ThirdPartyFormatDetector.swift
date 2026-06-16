//
//  ThirdPartyFormatDetector.swift
//  RecipeScalerCore
//

import Foundation
import ZIPFoundation

public enum ThirdPartyFormatDetector {
    public static func detect(url: URL) throws -> ThirdPartyFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "paprikarecipes":
            return .paprikaArchive
        case "paprikarecipe":
            return .paprikaSingle
        case "crumb":
            return .croutonSingle
        case "zip":
            return try detectZipContents(url: url)
        default:
            break
        }

        if isGzipData(at: url) {
            return .paprikaSingle
        }

        if isCroutonJSON(at: url) {
            return .croutonSingle
        }

        if openArchive(url: url) != nil {
            return try detectZipContents(url: url)
        }

        return .unsupported
    }

    public static func enumerateRecipeEntries(
        url: URL,
        format: ThirdPartyFormat
    ) throws -> [ThirdPartyArchiveEntry] {
        switch format {
        case .paprikaArchive, .croutonArchive:
            return try enumerateZipEntries(url: url, format: format)
        case .paprikaSingle:
            let data = try Data(contentsOf: url)
            return [ThirdPartyArchiveEntry(fileName: url.lastPathComponent, data: data)]
        case .croutonSingle:
            let data = try Data(contentsOf: url)
            return [ThirdPartyArchiveEntry(fileName: url.lastPathComponent, data: data)]
        case .unsupported:
            throw ThirdPartyImportError.unsupportedFormat
        }
    }

    public static func validateEntryCount(_ entries: [ThirdPartyArchiveEntry]) throws {
        guard entries.count <= ThirdPartyImportLimits.maxRecipesPerImport else {
            throw ThirdPartyImportError.recipeLimitExceeded(limit: ThirdPartyImportLimits.maxRecipesPerImport)
        }
    }

    /// Open archive for reading.
    ///
    /// We do NOT pass `preferredEncoding: .utf8` because in the current version of
    /// ZIPFoundation, that parameter only affects the `subscript[path]` lookup — the
    /// `entry.path` getter always derives the encoding from the ZIP general purpose
    /// bit flag (CP437 when the UTF-8 bit is unset). We handle encoding explicitly
    /// in `decodeEntryPath` instead.
    private static func openArchive(url: URL) -> Archive? {
        try? Archive(url: url, accessMode: .read)
    }

    /// Decode an entry path compensating for a known Crouton bug.
    ///
    /// Modern exporters (Crouton, Paprika) target iOS/macOS and always store filenames
    /// as UTF-8 bytes. Crouton writes UTF-8 filenames WITHOUT setting the UTF-8 general
    /// purpose bit flag (bit 11) in the ZIP central directory, which makes the default
    /// `entry.path` getter decode the bytes as CP437 → mojibake. We detect this by
    /// re-decoding the raw filename bytes as UTF-8: if it produces a valid non-ASCII
    /// string without replacement chars, we use it; otherwise we fall back to the
    /// spec-compliant default path.
    private static func decodeEntryPath(_ entry: Entry) -> String {
        let defaultPath = entry.path
        guard defaultPath.unicodeScalars.contains(where: { $0.value >= 0x80 }) else {
            return defaultPath
        }
        let utf8Decoded = entry.path(using: .utf8)
        if !utf8Decoded.isEmpty && !utf8Decoded.contains("\u{FFFD}") {
            return utf8Decoded
        }
        return defaultPath
    }

    private static func detectZipContents(url: URL) throws -> ThirdPartyFormat {
        guard let archive = openArchive(url: url) else {
            return .unsupported
        }

        let paths = archive.map(decodeEntryPath).filter { path in
            !path.hasPrefix("__MACOSX/") && !path.hasSuffix("/")
        }

        let paprika = paths.filter { $0.lowercased().hasSuffix(".paprikarecipe") }
        let crouton = paths.filter { $0.lowercased().hasSuffix(".crumb") }

        if !paprika.isEmpty && crouton.isEmpty {
            return .paprikaArchive
        }
        if !crouton.isEmpty && paprika.isEmpty {
            return .croutonArchive
        }
        return .unsupported
    }

    private static func enumerateZipEntries(
        url: URL,
        format: ThirdPartyFormat
    ) throws -> [ThirdPartyArchiveEntry] {
        guard let archive = openArchive(url: url) else {
            throw ThirdPartyImportError.unsupportedFormat
        }

        let suffix: String
        switch format {
        case .paprikaArchive:
            suffix = ".paprikarecipe"
        case .croutonArchive:
            suffix = ".crumb"
        default:
            throw ThirdPartyImportError.unsupportedFormat
        }

        var entries: [ThirdPartyArchiveEntry] = []
        for entry in archive {
            let path = decodeEntryPath(entry)
            guard path.lowercased().hasSuffix(suffix) else { continue }
            var data = Data()
            do {
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
            } catch {
                throw ThirdPartyImportError.corruptEntry(fileName: path)
            }
            guard !data.isEmpty else {
                throw ThirdPartyImportError.corruptEntry(fileName: path)
            }
            entries.append(ThirdPartyArchiveEntry(fileName: path, data: data))
        }

        if entries.isEmpty {
            throw ThirdPartyImportError.emptyArchive
        }

        entries.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        return entries
    }

    private static func isGzipData(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 2), prefix.count == 2 else { return false }
        return prefix[0] == 0x1f && prefix[1] == 0x8b
    }

    private static func isCroutonJSON(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["uuid"] is String && object["ingredients"] is [[String: Any]]
    }
}
