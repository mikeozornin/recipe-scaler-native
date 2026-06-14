//
//  ImportErrorLocalizer.swift
//  RecipeScalerCore
//
//  Maps server-side import errors and validation errors to localized keys.
//
//  When called from the main app, pass `bundle: .main` (default) so that
//  strings resolve from the main `Localizable.xcstrings`.
//
//  When called from a Share/Action extension, pass `bundle: .module` to
//  resolve from the framework's `Shared.xcstrings` resource bundle.
//

import Foundation

public enum ImportErrorLocalizer {

    /// Localize an arbitrary error using a `bundle` for string lookups.
    /// - Parameters:
    ///   - error: error thrown by `RecipeImportAPI` or `ImportPhotoValidator`.
    ///   - bundle: bundle containing `Localizable` / `Shared` strings table.
    public static func localize(_ error: Error, bundle: Bundle = .main) -> String {
        // Validation errors from ImportPhotoValidator carry a key in errorDescription.
        if let validation = error as? ImportPhotoValidator.ValidationError {
            switch validation {
            case .tooMany:
                return pluralized(
                    "import.error-too-many-photos",
                    count: ImportPhotoValidator.maxImages,
                    bundle: bundle
                )
            default:
                return resolve(validation.errorDescription ?? "import.error", bundle: bundle)
            }
        }

        let message = error.localizedDescription

        // Direct server-provided key.
        if message.hasPrefix("import.") {
            return localizeImportKey(message, bundle: bundle)
        }

        // Known server phrases (mirrors web).
        if message.contains("size exceeds") && message.contains("MB limit") {
            return resolve("import.error-photo-too-large", bundle: bundle)
        }
        if message.contains("captcha") || message.contains("anti-bot") {
            return resolve("import.error-captcha", bundle: bundle)
        }
        if message.contains("Could not extract content with any static method") {
            return resolve("import.error-static", bundle: bundle)
        }
        if message.contains("Invalid response from server") {
            return resolve("import.error-invalid-response", bundle: bundle)
        }
        if message.contains("Could not process image") {
            return resolve("import.error-photo-corrupt", bundle: bundle)
        }
        if message.contains("up to") && message.contains("recipes at a time") {
            let count = parseCount(from: message) ?? ImportPhotoValidator.maxRecipes
            return pluralized("import.error-too-many-recipes", count: count, bundle: bundle)
        }
        if message.contains("up to") && message.contains("photos at a time") {
            let count = parseCount(from: message) ?? ImportPhotoValidator.maxImages
            return pluralized("import.error-too-many-photos", count: count, bundle: bundle)
        }
        if message.contains("Failed to import recipe") {
            return resolve("import.error", bundle: bundle)
        }

        return message
    }

    /// Wrapper around `Bundle.localizedString` that returns the key itself when
    /// the value is missing (matches the project convention — missing keys are
    /// visible, not masked).
    private static func resolve(_ key: String, bundle: Bundle) -> String {
        bundle.localizedString(forKey: key, value: nil, table: stringsTable(for: bundle))
    }

    private static func stringsTable(for bundle: Bundle) -> String? {
        bundle == .main ? nil : "Shared"
    }

    /// Resolve echoed `import.*` keys; plural limits use the configured max, not selection size.
    private static func localizeImportKey(_ key: String, bundle: Bundle) -> String {
        let baseKey = key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
        switch baseKey {
        case "import.error-too-many-photos":
            return pluralized(baseKey, count: ImportPhotoValidator.maxImages, bundle: bundle)
        case "import.error-too-many-recipes":
            return pluralized(baseKey, count: ImportPhotoValidator.maxRecipes, bundle: bundle)
        default:
            return resolve(key, bundle: bundle)
        }
    }

    /// Select the correct plural form for `key` using `count` and format it.
    private static func pluralized(_ key: String, count: Int, bundle: Bundle) -> String {
        Bundle.pluralizedString(
            key: key,
            count: count,
            table: stringsTable(for: bundle),
            locale: Locale.current,
            localizedString: { bundle.localizedString(forKey: $0, value: nil, table: $1) }
        )
    }

    /// Best-effort extraction of the first integer from a server message such as
    /// "You can import up to 25 recipes at a time."
    private static func parseCount(from message: String) -> Int? {
        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range, in: message) else {
            return nil
        }
        return Int(message[range])
    }
}
