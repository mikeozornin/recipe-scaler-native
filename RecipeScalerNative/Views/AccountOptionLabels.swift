//
//  AccountOptionLabels.swift
//  RecipeScalerNative
//

import SwiftUI

extension PublicShareMode {
    var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .all: "account.share-mode.all"
        case .with_images_and_steps: "account.share-mode.with-images"
        case .one_by_one: "account.share-mode.one-by-one"
        }
    }

    var localizedTitle: String {
        switch self {
        case .all: String(localized: LocalizedStringResource("account.share-mode.all"))
        case .with_images_and_steps: String(localized: LocalizedStringResource("account.share-mode.with-images"))
        case .one_by_one: String(localized: LocalizedStringResource("account.share-mode.one-by-one"))
        }
    }
}

extension AppLanguagePreference {
    var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .en: "account.language.en"
        case .ru: "account.language.ru"
        }
    }

    var localizedTitle: String {
        switch self {
        case .en: String(localized: LocalizedStringResource("account.language.en"))
        case .ru: String(localized: LocalizedStringResource("account.language.ru"))
        }
    }
}

extension AppThemePreference {
    var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .system: "account.theme.system"
        case .light: "account.theme.light"
        case .dark: "account.theme.dark"
        }
    }

    var localizedTitle: String {
        switch self {
        case .system: String(localized: LocalizedStringResource("account.theme.system"))
        case .light: String(localized: LocalizedStringResource("account.theme.light"))
        case .dark: String(localized: LocalizedStringResource("account.theme.dark"))
        }
    }
}

extension RecipeFolderRoutes.CollectionsRootLayout {
    var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .list: "account.collections-layout.list"
        case .folders: "account.collections-layout.folders"
        }
    }

    var localizedTitle: String {
        switch self {
        case .list: String(localized: LocalizedStringResource("account.collections-layout.list"))
        case .folders: String(localized: LocalizedStringResource("account.collections-layout.folders"))
        }
    }
}