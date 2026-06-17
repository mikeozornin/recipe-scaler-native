//
//  NativeImportMessageLocalizer.swift
//  RecipeScalerNative
//

import Foundation

enum NativeImportMessageLocalizer {
    static func recipeFailed(name: String, error: Error) -> String {
        String(
            format: Bundle.currentLocalizedString("account.data.import.recipe-failed %@ %@"),
            locale: AppLanguagePreference.current.locale,
            name,
            UserFacingAPIError.message(for: error)
        )
    }

    static func imagesOffline(count: Int) -> String {
        String(
            format: Bundle.currentLocalizedString("account.data.import.images-offline %d"),
            locale: AppLanguagePreference.current.locale,
            count
        )
    }

    static func imageFailed(name: String) -> String {
        String(
            format: Bundle.currentLocalizedString("account.data.import.image-failed %@"),
            locale: AppLanguagePreference.current.locale,
            name
        )
    }

    static func imageTooLarge(name: String) -> String {
        String(
            format: Bundle.currentLocalizedString("account.data.import.image-too-large %@"),
            locale: AppLanguagePreference.current.locale,
            name
        )
    }
}
