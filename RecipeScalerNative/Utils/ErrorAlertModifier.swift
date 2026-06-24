//
//  ErrorAlertModifier.swift
//  RecipeScalerNative
//
//  Bridges a `String?` error message into `.alert(isPresented:)`, replacing the
//  `Binding(get: { message != nil }, set: { if !$0 { message = nil } })` boilerplate
//  duplicated across error sites. Title and OK button resolve through
//  `Bundle.currentLocalizedString` so they honor the in-app language override
//  (see LocalizedNavigationTitle.swift for the same pattern).
//

import SwiftUI

extension View {
    /// Presents a localized error alert bound to an optional error message.
    ///
    /// - Parameters:
    ///   - titleKey: Localizable.xcstrings key for the alert title.
    ///     Defaults to `common.error`.
    ///   - message: Source of truth for the error text. `nil` hides the alert;
    ///     a non-nil value presents it. Reset to `nil` automatically on dismiss.
    func errorAlert(
        title titleKey: String = "common.error",
        message: Binding<String?>
    ) -> some View {
        modifier(ErrorAlertModifier(titleKey: titleKey, message: message))
    }
}

private struct ErrorAlertModifier: ViewModifier {
    let titleKey: String
    @Binding var message: String?
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        _ = locale
        let title = Bundle.currentLocalizedString(titleKey)
        let ok = Bundle.currentLocalizedString("common.ok")
        return content.alert(
            Text(verbatim: title),
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button(role: .cancel) {} label: {
                Text(verbatim: ok)
            }
        } message: {
            Text(message ?? "")
        }
    }
}
