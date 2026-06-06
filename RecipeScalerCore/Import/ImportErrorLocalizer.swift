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
            return resolve(validation.errorDescription ?? "import.error", bundle: bundle)
        }

        let message = error.localizedDescription

        // Direct server-provided key.
        if message.hasPrefix("import.") {
            return resolve(message, bundle: bundle)
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
            return resolve("import.error-too-many-recipes", bundle: bundle)
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
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value
    }
}
