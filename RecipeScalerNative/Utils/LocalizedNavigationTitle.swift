//
//  LocalizedNavigationTitle.swift
//  RecipeScalerNative
//
//  Navigation title that refreshes when the in-app language is switched at runtime.
//

import SwiftUI

extension View {
    /// A navigation title that updates when `AppLanguagePreference` switches the language.
    ///
    /// `.navigationTitle(Text("key"))` stores the *localization key*, so after a language
    /// flip the new title compares equal to the old one and SwiftUI never pushes the
    /// re-resolved string to UIKit — the bar keeps the previous title until the view is
    /// rebuilt. Here we resolve the string eagerly from the selected language bundle
    /// (`Bundle.currentLocalizedString` — `String(localized:)` does NOT reliably honor the
    /// runtime override and falls back to the development language) and pass it as a
    /// verbatim `Text`, so the value genuinely changes. Reading `\.locale` forces this
    /// modifier to re-evaluate when the language switches.
    ///
    /// - Parameter key: the `Localizable.xcstrings` key for the title.
    func localizedNavigationTitle(_ key: String) -> some View {
        modifier(LocalizedNavigationTitleModifier(key: key))
    }
}

private struct LocalizedNavigationTitleModifier: ViewModifier {
    let key: String
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        // Reading `locale` is the dependency that re-runs this body on a language switch.
        _ = locale
        return content.navigationTitle(Text(verbatim: Bundle.currentLocalizedString(key)))
    }
}
