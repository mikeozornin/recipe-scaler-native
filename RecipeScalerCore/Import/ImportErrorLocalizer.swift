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

    private static let sizeMb = Int(ImportPhotoValidator.maxImageBytes / 1_000_000)

    private static let failedRecipePattern = #"^Failed to import recipe "([\s\S]+?)": ([\s\S]+)$"#

    /// Localize an arbitrary error using a `bundle` for string lookups.
    /// - Parameters:
    ///   - error: error thrown by `RecipeImportAPI` or `ImportPhotoValidator`.
    ///   - bundle: bundle containing `Localizable` / `Shared` strings table.
    ///     Pass `.main` for the app, `.module` for Share/Action extensions.
    ///   - locale: locale for plural form selection and `String(format:)`.
    ///     Defaults to `Locale.current`.
    public static func localize(_ error: Error, bundle: Bundle = .main, locale: Locale = .current) -> String {
        // Validation errors from ImportPhotoValidator carry a dot-key+args in errorDescription.
        if let validation = error as? ImportPhotoValidator.ValidationError {
            switch validation {
            case .tooMany:
                return pluralized(
                    "import.error-too-many-photos",
                    count: ImportPhotoValidator.maxImages,
                    bundle: bundle,
                    locale: locale
                )
            default:
                return localizeImportKey(validation.errorDescription ?? "import.error", bundle: bundle, locale: locale)
            }
        }

        return localize(error.localizedDescription, bundle: bundle, locale: locale)
    }

    /// Localize a raw server-side error message string.
    public static func localize(_ rawMessage: String, bundle: Bundle = .main, locale: Locale = .current) -> String {
        // 1. Already a known `import.*` key (server can echo our keys back).
        if rawMessage.hasPrefix("import.") {
            return localizeImportKey(rawMessage, bundle: bundle, locale: locale)
        }

        // 2. Size / captcha / static / invalid response — phrases the server emits.
        if rawMessage.contains("size exceeds") && rawMessage.contains("MB limit") {
            return translate("import.error-photo-too-large", substitutions: ["sizeMb": sizeMb], bundle: bundle, locale: locale)
        }

        switch rawMessage {
        case "Source page is protected by a captcha or anti-bot challenge",
             "HTTP 403: Forbidden":
            return translate("import.error-captcha", bundle: bundle, locale: locale)
        case "Could not extract content with any static method":
            return translate("import.error-static", bundle: bundle, locale: locale)
        case "Invalid response from server":
            return translate("import.error-invalid-response", bundle: bundle, locale: locale)
        case "Failed to import recipe":
            return translate("import.error", bundle: bundle, locale: locale)
        default:
            break
        }

        // Upstream fetch failures from recipe-extraction (`HTTP ${status}: …`).
        if rawMessage.hasPrefix("HTTP 403:") || rawMessage.hasPrefix("HTTP 429:") {
            return translate("import.error-captcha", bundle: bundle, locale: locale)
        }
        if rawMessage.hasPrefix("HTTP 404:") {
            return translate("import.error-static", bundle: bundle, locale: locale)
        }

        // OpenRouter / LLM upstream failures bubbled as 500 from import routes.
        if rawMessage.hasPrefix("LLM request failed:")
            || rawMessage.hasPrefix("Assistant LLM request failed:") {
            return translate("llm.parse-error", bundle: bundle, locale: locale)
        }

        if rawMessage.hasPrefix("Could not process image:") {
            return translate("import.error-photo-corrupt", bundle: bundle, locale: locale)
        }

        // 3. Per-recipe failure with details — preserve the inner details verbatim.
        if let regex = try? NSRegularExpression(pattern: failedRecipePattern, options: []),
           let match = regex.firstMatch(
               in: rawMessage,
               range: NSRange(rawMessage.startIndex..., in: rawMessage)
           ),
           let nameRange = Range(match.range(at: 1), in: rawMessage),
           let detailsRange = Range(match.range(at: 2), in: rawMessage) {
            let template = translate("import.validation.recipe-import-failed", bundle: bundle, locale: locale)
            return String(
                format: template,
                locale: locale,
                String(rawMessage[nameRange]),
                String(rawMessage[detailsRange])
            )
        }

        // 4. Servings validation phrase from server.
        if rawMessage == "servings must be a finite number greater than 0 if present" {
            return translate("import.validation.invalid-servings", bundle: bundle, locale: locale)
        }

        // 5. URL count limit — server-supplied or echoed.
        if rawMessage.contains("up to") && rawMessage.contains("recipes at a time") {
            let count = parseCount(from: rawMessage) ?? ImportPhotoValidator.maxRecipes
            return pluralized("import.error-too-many-recipes", count: count, bundle: bundle, locale: locale)
        }

        // 6. Photo count limit.
        if rawMessage.contains("up to") && rawMessage.contains("photos at a time") {
            let count = parseCount(from: rawMessage) ?? ImportPhotoValidator.maxImages
            return pluralized("import.error-too-many-photos", count: count, bundle: bundle, locale: locale)
        }

        return rawMessage.isEmpty ? translate("import.error", bundle: bundle, locale: locale) : rawMessage
    }

    // MARK: - Internals

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
    private static func localizeImportKey(_ key: String, bundle: Bundle, locale: Locale) -> String {
        let baseKey = key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
        switch baseKey {
        case "import.error-too-many-photos":
            return pluralized(baseKey, count: ImportPhotoValidator.maxImages, bundle: bundle, locale: locale)
        case "import.error-too-many-recipes":
            return pluralized(baseKey, count: ImportPhotoValidator.maxRecipes, bundle: bundle, locale: locale)
        default:
            return resolve(key, bundle: bundle)
        }
    }

    /// Select the correct plural form for `key` using `count` and format it.
    private static func pluralized(_ key: String, count: Int, bundle: Bundle, locale: Locale) -> String {
        Bundle.pluralizedString(
            key: key,
            count: count,
            table: stringsTable(for: bundle),
            locale: locale,
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

    /// Resolve a key and optionally substitute ICU `{{name}}` placeholders with
    /// positional `%d` / `%@` arguments (web uses ICU, xcstrings uses positional).
    private static func translate(_ key: String, substitutions: [String: Int] = [:], bundle: Bundle, locale: Locale) -> String {
        let template = resolve(key, bundle: bundle)
        if substitutions.isEmpty {
            return template
        }

        var resolved = template
        var args: [CVarArg] = []
        for (placeholder, value) in substitutions {
            let token = "{{\(placeholder)}}"
            if resolved.contains(token) {
                resolved = resolved.replacingOccurrences(of: token, with: "%d")
                args.append(value)
            }
        }

        return String(format: resolved, locale: locale, arguments: args)
    }
}
