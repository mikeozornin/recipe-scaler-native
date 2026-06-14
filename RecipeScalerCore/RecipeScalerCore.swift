//
//  RecipeScalerCore.swift
//  RecipeScalerCore
//
//  Module entry point. The framework is a Cocoa Touch Framework that
//  bundles shared network/import/auth code used by both the main app
//  and the Share/Action extensions.
//
//  All public types are exported automatically; this file intentionally
//  does not declare additional public surface.
//

import Foundation

// MARK: - Localization helpers
// Merged from RecipeScalerCore/Utils/Bundle+RecipeScalerCoreLocalization.swift

public extension Bundle {
    /// Resolve a localized string through the main app bundle.
    ///
    /// When the host app has installed the language-override swizzle, this routes
    /// lookups to the user-selected `.lproj` bundle. Use this from share/action
    /// extensions and other `RecipeScalerCore` contexts that cannot import the main
    /// app's localization helpers directly.
    static func rcLocalizedString(_ key: String, table: String? = nil) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: table)
    }
}

// MARK: - Pluralization
// Merged from RecipeScalerCore/Utils/Pluralization.swift

/// CLDR plural categories supported by this helper.
public enum PluralCategory: String, CaseIterable, Sendable {
    case zero
    case one
    case two
    case few
    case many
    case other
}

public extension Locale {
    /// Return the CLDR plural category for `count` in this locale.
    ///
    /// Supports Russian (one/few/many) and English (one/other). Other languages fall
    /// back to English rules, which is sufficient for the current `en`/`ru` app scope.
    func pluralCategory(for count: Int) -> PluralCategory {
        switch language.languageCode?.identifier {
        case "ru", "uk", "be":
            let mod10 = count % 10
            let mod100 = count % 100
            if mod10 == 1 && mod100 != 11 { return .one }
            if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) { return .few }
            if mod10 == 0 || (mod10 >= 5 && mod10 <= 9) || (mod100 >= 11 && mod100 <= 14) { return .many }
            return .other
        default:
            return count == 1 ? .one : .other
        }
    }
}

public extension Bundle {
    /// Format a count-dependent localized string by selecting the correct plural form.
    ///
    /// The helper looks for keys in this order:
    ///   1. `key.<category>` (e.g. `discover.collection.recipe-count.few`)
    ///   2. `key.other`
    ///   3. `key.many`
    ///   4. `key`
    ///
    /// Missing translations (where the lookup returns the key itself) are skipped.
    ///
    /// - Parameters:
    ///   - key: Base localization key.
    ///   - count: The number controlling plural form and substituted into the string.
    ///   - table: Optional strings table name.
    ///   - locale: Locale used for plural-rule selection and number formatting.
    ///     Defaults to `Locale.current`.
    ///   - localizedString: Resolver for concrete strings. Defaults to
    ///     `Bundle.rcLocalizedString(_:table:)`, which routes through the main bundle.
    static func pluralizedString(
        key: String,
        count: Int,
        table: String? = nil,
        locale: Locale? = nil,
        localizedString: @escaping (String, String?) -> String = { rcLocalizedString($0, table: $1) }
    ) -> String {
        let effectiveLocale = locale ?? .current
        let category = effectiveLocale.pluralCategory(for: count)
        let candidates = [
            "\(key).\(category.rawValue)",
            "\(key).other",
            "\(key).many",
            key
        ]
        let template = candidates
            .lazy
            .map { (candidate: $0, value: localizedString($0, table)) }
            .first { $0.value != $0.candidate }?
            .value ?? key
        return String(format: template, locale: effectiveLocale, count)
    }
}
