//
//  GuideAssetResolver.swift
//  RecipeScalerNative
//
//  Spec 040 — resolves a logical guide asset name to the best available
//  runtime asset:
//   1. Try `<base>_<lang-code>_<appearance>`.
//   2. Try `<base>_<lang-code>`.
//   3. Try `<base>_<appearance>`.
//   4. Fall back to `<base>` (universal / English-master imageset).
//   5. If nothing exists, return nil → caller renders `GuideAssetPlaceholder`.
//
//  Language code follows `AppLanguagePreference.current` (ru / en).
//

import SwiftUI

enum GuideAssetResolver {
    /// Returns a ready-to-render `Image` for the asset, or `nil` if neither
    /// the localized nor the base imageset is present in the bundle.
    static func image(forBaseName baseName: String) -> Image? {
        for name in candidateNames(forBaseName: baseName) {
            if hasBundledImage(named: name) {
                return Image(name)
            }
        }
        return nil
    }

    /// True if either the localized or the base imageset is bundled.
    static func hasImage(forBaseName baseName: String) -> Bool {
        candidateNames(forBaseName: baseName).contains { hasBundledImage(named: $0) }
    }

    static func candidateNames(forBaseName baseName: String) -> [String] {
        let language = AppLanguagePreference.current.rawValue
        let appearance = AppThemePreference.current == .dark ? "dark" : "light"
        return [
            "\(baseName)_\(language)_\(appearance)",
            "\(baseName)_\(language)",
            "\(baseName)_\(appearance)",
            baseName
        ]
    }

    static func videoURL(forResourceName resourceName: String) -> URL? {
        let language = AppLanguagePreference.current.rawValue
        let appearance = AppThemePreference.current == .dark ? "dark" : "light"
        let candidates = [
            "\(resourceName)_\(language)_\(appearance)",
            "\(resourceName)_\(language)",
            "\(resourceName)_\(appearance)",
            resourceName
        ]
        return candidates.lazy
            .compactMap { Bundle.main.url(forResource: $0, withExtension: "mp4") }
            .first
    }

    /// Wraps `UIImage(named:)` so this file stays testable without SwiftUI.
    private static func uiImage(named name: String) -> UIImage? {
        UIImage(named: name)
    }

    /// Whether the bundle has an image named `name`. The asset catalog does not change
    /// at runtime, so each name is looked up (and decoded) once, not on every body pass.
    static func hasBundledImage(named name: String) -> Bool {
        existenceLock.lock()
        if let known = existenceByName[name] {
            existenceLock.unlock()
            return known
        }
        existenceLock.unlock()

        let exists = uiImage(named: name) != nil
        existenceLock.lock()
        existenceByName[name] = exists
        existenceLock.unlock()
        return exists
    }

    private static let existenceLock = NSLock()
    private nonisolated(unsafe) static var existenceByName: [String: Bool] = [:]
}
