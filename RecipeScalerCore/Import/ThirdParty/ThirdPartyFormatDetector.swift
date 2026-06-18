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

    /// Cheap central-directory count of recipe entries in a ZIP-backed format.
    /// Reads only the ZIP central directory (no decompression). Returns `nil` for
    /// single-file formats or if the archive cannot be opened.
    public static func estimatedRecipeCount(
        url: URL,
        format: ThirdPartyFormat
    ) -> Int? {
        guard format == .paprikaArchive || format == .croutonArchive else { return nil }
        guard let archive = try? Archive(url: url, accessMode: .read) else { return nil }
        let suffix: String
        switch format {
        case .paprikaArchive: suffix = ".paprikarecipe"
        case .croutonArchive: suffix = ".crumb"
        default: return nil
        }
        return archive.reduce(into: 0) { acc, entry in
            if entry.path.lowercased().hasSuffix(suffix) { acc += 1 }
        }
    }

    public static func enumerateRecipeEntries(
        url: URL,
        format: ThirdPartyFormat,
        maxEntryBytes: Int = .max,
        maxArchiveBytes: Int = .max
    ) async throws -> [ThirdPartyArchiveEntry] {
        // Thin wrapper around the streaming variant for callers that still want the full
        // array in memory (existing tests, `validateEntryCount` on count, etc.). Iteration
        // semantics (including the `recipeLimitExceeded` guard) are identical.
        var collected: [ThirdPartyArchiveEntry] = []
        let stream = enumerateRecipeEntriesStream(
            url: url,
            format: format,
            maxEntryBytes: maxEntryBytes,
            maxArchiveBytes: maxArchiveBytes
        )
        for try await entry in stream {
            collected.append(entry)
        }
        collected.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        return collected
    }

    /// Streaming variant of `enumerateRecipeEntries`. Yields one decoded entry at a time
    /// so per-entry `Data` is released before the next iteration, keeping peak memory
    /// bounded regardless of archive size. Enforces `maxRecipesPerImport` mid-stream
    /// (throws as soon as the count would exceed the limit) — callers do NOT need to call
    /// `validateEntryCount` after iterating.
    ///
    /// - Parameters:
    ///   - maxEntryBytes: Per-entry decompressed byte cap (defense vs decompression bombs).
    ///     Defaults to `.max` (backward compatible). Real call sites should pass
    ///     `ThirdPartyImportLimits.maxDecompressedEntryBytes`.
    ///   - maxArchiveBytes: Aggregate decompressed byte cap across all entries.
    ///     Defaults to `.max`. Real call sites should pass
    ///     `ThirdPartyImportLimits.maxDecompressedArchiveBytes`.
    ///
    /// Single-file formats (`.paprikaSingle`, `.croutonSingle`) yield exactly one entry.
    public static func enumerateRecipeEntriesStream(
        url: URL,
        format: ThirdPartyFormat,
        maxEntryBytes: Int = .max,
        maxArchiveBytes: Int = .max
    ) -> AsyncThrowingStream<ThirdPartyArchiveEntry, Error> {
        AsyncThrowingStream { continuation in
            // Pre-decide single-file paths synchronously to keep Archive lifecycle inside the task.
            if format == .paprikaSingle || format == .croutonSingle {
                do {
                    let data = try Data(contentsOf: url)
                    continuation.yield(ThirdPartyArchiveEntry(fileName: url.lastPathComponent, data: data))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                return
            }

            guard format == .paprikaArchive || format == .croutonArchive else {
                continuation.finish(throwing: ThirdPartyImportError.unsupportedFormat)
                return
            }

            Task.detached(priority: .userInitiated) {
                let result: Result<Void, Error> = await Self.yieldZipEntries(
                    url: url,
                    format: format,
                    maxEntryBytes: maxEntryBytes,
                    maxArchiveBytes: maxArchiveBytes,
                    continuation: continuation
                )
                switch result {
                case .success:
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Drives the ZIP-extraction loop on a background executor. Each yielded
    /// `ThirdPartyArchiveEntry.data` is freed by ARC after the consumer is done with it.
    private static func yieldZipEntries(
        url: URL,
        format: ThirdPartyFormat,
        maxEntryBytes: Int,
        maxArchiveBytes: Int,
        continuation: AsyncThrowingStream<ThirdPartyArchiveEntry, Error>.Continuation
    ) async -> Result<Void, Error> {
        let archive: Archive
        do {
            guard let opened = try? Archive(url: url, accessMode: .read) else {
                return .failure(ThirdPartyImportError.unsupportedFormat)
            }
            archive = opened
        }

        let suffix: String
        switch format {
        case .paprikaArchive: suffix = ".paprikarecipe"
        case .croutonArchive: suffix = ".crumb"
        default: return .failure(ThirdPartyImportError.unsupportedFormat)
        }

        var count = 0
        var seenAny = false
        var archiveRunningTotal = 0

        // Stable iteration: ZIPFoundation `Archive` conforms to `Sequence`. We iterate in
        // natural central-directory order and let callers sort when they need determinism.
        for entry in archive {
            // Soft cancellation: if downstream breaks out, stop extracting.
            if Task.isCancelled { return .success(()) }

            let path = decodeEntryPath(entry)
            guard path.lowercased().hasSuffix(suffix) else { continue }

            count += 1
            if count > ThirdPartyImportLimits.maxRecipesPerImport {
                return .failure(ThirdPartyImportError.recipeLimitExceeded(
                    limit: ThirdPartyImportLimits.maxRecipesPerImport
                ))
            }

            // B1: pre-flight check against the central-directory `uncompressedSize`.
            // Cheap (no decompression). Catches the common case of a CD that
            // honestly reports an oversized entry.
            let declaredSize = Int(entry.uncompressedSize)
            if declaredSize > maxEntryBytes {
                return .failure(ThirdPartyImportError.entrySizeLimitExceeded(fileName: path))
            }
            // B3: pre-flight aggregate check (uses CD's declared size).
            if archiveRunningTotal + declaredSize > maxArchiveBytes {
                return .failure(ThirdPartyImportError.archiveSizeLimitExceeded(fileName: path))
            }

            // B2: streaming running total — catches the case where the central
            // directory lies (spoofed `uncompressedSize`) and the entry
            // decompresses to more than `maxEntryBytes` for real.
            var data = Data()
            var entryRunningTotal = 0
            var streamingOverflow: ThirdPartyImportError?
            do {
                _ = try archive.extract(entry) { chunk in
                    entryRunningTotal += chunk.count
                    if entryRunningTotal > maxEntryBytes {
                        streamingOverflow = .entrySizeLimitExceeded(fileName: path)
                        return
                    }
                    if archiveRunningTotal + entryRunningTotal > maxArchiveBytes {
                        streamingOverflow = .archiveSizeLimitExceeded(fileName: path)
                        return
                    }
                    data.append(chunk)
                }
            } catch {
                return .failure(ThirdPartyImportError.corruptEntry(fileName: path))
            }
            if let overflow = streamingOverflow {
                return .failure(overflow)
            }
            guard !data.isEmpty else {
                return .failure(ThirdPartyImportError.corruptEntry(fileName: path))
            }

            archiveRunningTotal += data.count
            seenAny = true
            continuation.yield(ThirdPartyArchiveEntry(fileName: path, data: data))
        }

        guard seenAny else {
            return .failure(ThirdPartyImportError.emptyArchive)
        }
        return .success(())
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

    private static func isGzipData(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 2), prefix.count == 2 else { return false }
        return prefix[0] == 0x1f && prefix[1] == 0x8b
    }

    private static func isCroutonJSON(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              // #32: pre-flight — oversized files cannot be Crouton JSON manifests.
              data.count <= ThirdPartyImportLimits.maxRecipeJSONBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["uuid"] is String && object["ingredients"] is [[String: Any]]
    }
}
