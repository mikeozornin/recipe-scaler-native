//
//  ImportErrorLocalizer.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Mirrors `recipe-scaler-web/recipe-scaler/src/utils/import-error-message.ts`.
/// Maps server-side error strings (and our own `import.*` keys) to localized user-facing text.
enum ImportErrorLocalizer {

    private static let sizeMb = Int(ImportPhotoValidator.maxImageBytes / 1_000_000)

    private static let failedRecipePattern = #"^Failed to import recipe "([\s\S]+?)": ([\s\S]+)$"#

    /// Convert an error (or server-supplied message) into a localized user-facing string.
    static func localize(_ error: Error) -> String {
        let raw = error.localizedDescription

        // Re-use our own validation keys — they already resolve to localized strings.
        if let validation = error as? ImportPhotoValidator.ValidationError {
            return validation.errorDescription ?? validation.localizationKey
        }

        return localize(raw)
    }

    /// Localize a raw server-side error message string.
    static func localize(_ rawMessage: String) -> String {
        // 1. Already a known `import.*` key (server can echo our keys back).
        if rawMessage.hasPrefix("import.") {
            return localizeImportKey(rawMessage)
        }

        // 2. Captcha / static / invalid response — exact-match phrases the server emits.
        if rawMessage.contains("size exceeds") && rawMessage.contains("MB limit") {
            return translate("import.error-photo-too-large", substitutions: ["sizeMb": sizeMb])
        }

        switch rawMessage {
        case "Source page is protected by a captcha or anti-bot challenge":
            return translate("import.error-captcha")
        case "Could not extract content with any static method":
            return translate("import.error-static")
        case "Invalid response from server":
            return translate("import.error-invalid-response")
        case "Failed to import recipe":
            return translate("import.error")
        default:
            break
        }

        if rawMessage.hasPrefix("Could not process image:") {
            return translate("import.error-photo-corrupt")
        }

        // 3. Per-recipe failure with details — preserve the inner details verbatim.
        if let regex = try? NSRegularExpression(pattern: failedRecipePattern, options: []),
           let match = regex.firstMatch(
               in: rawMessage,
               range: NSRange(rawMessage.startIndex..., in: rawMessage)
           ),
           let nameRange = Range(match.range(at: 1), in: rawMessage),
           let detailsRange = Range(match.range(at: 2), in: rawMessage) {
            let template = translate("import.validation.recipe-import-failed")
            return String(
                format: template,
                locale: AppLanguagePreference.current.locale,
                String(rawMessage[nameRange]),
                String(rawMessage[detailsRange])
            )
        }

        // 4. Servings validation phrase from server.
        if rawMessage == "servings must be a finite number greater than 0 if present" {
            return translate("import.validation.invalid-servings")
        }

        // 5. URL count limit — server-supplied or echoed.
        if rawMessage.contains("up to") && rawMessage.contains("recipes at a time") {
            let count = parseCount(from: rawMessage) ?? RecipeScalerCore.ImportPhotoValidator.maxRecipes
            return Bundle.appPluralizedString(key: "import.error-too-many-recipes", count: count)
        }

        // 6. Photo count limit.
        if rawMessage.contains("up to") && rawMessage.contains("photos at a time") {
            let count = parseCount(from: rawMessage) ?? ImportPhotoValidator.maxImages
            return Bundle.appPluralizedString(key: "import.error-too-many-photos", count: count)
        }

        return rawMessage.isEmpty ? translate("import.error") : rawMessage
    }

    private static func localizeImportKey(_ key: String) -> String {
        let baseKey = key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
        switch baseKey {
        case "import.error-too-many-photos":
            return Bundle.appPluralizedString(
                key: baseKey,
                count: ImportPhotoValidator.maxImages
            )
        case "import.error-too-many-recipes":
            return Bundle.appPluralizedString(
                key: baseKey,
                count: RecipeScalerCore.ImportPhotoValidator.maxRecipes
            )
        default:
            return translate(baseKey)
        }
    }

    private static func parseCount(from message: String) -> Int? {
        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range, in: message) else {
            return nil
        }
        return Int(message[range])
    }

    private static func translate(_ key: String, substitutions: [String: Int] = [:]) -> String {
        if substitutions.isEmpty {
            return Bundle.currentLocalizedString(key)
        }

        let template = Bundle.currentLocalizedString(key)
        // Web uses ICU `{{name}}` interpolation; xcstrings uses positional `%d` / `%@`.
        // Replace `{{name}}` placeholders with positional `%d` in declaration order.
        var resolved = template
        var args: [CVarArg] = []
        for (placeholder, value) in substitutions {
            let token = "{{\(placeholder)}}"
            if resolved.contains(token) {
                resolved = resolved.replacingOccurrences(of: token, with: "%d")
                args.append(value)
            }
        }

        return String(format: resolved, locale: AppLanguagePreference.current.locale, arguments: args)
    }
}
