//
//  GuideAssetResolver.swift
//  RecipeScalerNative
//
//  Spec 040 — resolves a logical guide asset name to the best available
//  runtime asset:
//   1. Try `<base>_<lang-code>` imageset (e.g. `guide_sent_assistant_message_ex_01_ru`).
//   2. Fall back to `<base>` (universal / English-master imageset).
//   3. If neither exists, return nil → caller renders `GuideAssetPlaceholder`.
//
//  Language code follows `AppLanguagePreference.current` (ru / en).
//

import SwiftUI

enum GuideAssetResolver {
    /// Returns a ready-to-render `Image` for the asset, or `nil` if neither
    /// the localized nor the base imageset is present in the bundle.
    static func image(forBaseName baseName: String) -> Image? {
        let langCode = AppLanguagePreference.current.rawValue // "ru" | "en"
        let localizedName = "\(baseName)_\(langCode)"

        if uiImage(named: localizedName) != nil {
            return Image(localizedName)
        }
        if uiImage(named: baseName) != nil {
            return Image(baseName)
        }
        return nil
    }

    /// True if either the localized or the base imageset is bundled.
    static func hasImage(forBaseName baseName: String) -> Bool {
        uiImage(named: "\(baseName)_\(AppLanguagePreference.current.rawValue)") != nil
            || uiImage(named: baseName) != nil
    }

    /// Wraps `UIImage(named:)` so this file stays testable without SwiftUI.
    private static func uiImage(named name: String) -> UIImage? {
        UIImage(named: name)
    }
}
