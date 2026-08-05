//
//  SystemBannerView.swift
//  RecipeScalerNative
//
//  Spec 061 — dismissible server-published system banner over the recipe list.
//
//  Renders the active banner payload from `SystemBannerStore`. The server ships
//  literal strings for `ru` and `en`; the view picks the variant by the current
//  `AppLanguagePreference`. Server-driven content must be drawn with
//  `Text(verbatim:)` — `Text(message)` would treat the string as a localization
//  key (see docs/I18N.md §"Runtime content").
//
//  Visual template: `LegacyAuthBannerView` + `DatabaseInitFailedBanner` in
//  `RecipeListView`. Uses semantic system colors so light/dark adaptation is
//  automatic — no explicit colorScheme branching required.
//

import SwiftUI

struct SystemBannerView: View {
    let banner: SystemBannerDTO
    let onDismiss: () -> Void

    @Environment(\.locale) private var locale

    private var languageCode: String {
        AppLanguagePreference.current.rawValue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: banner.title(for: languageCode))
                    .appHeadline()
                    .fixedSize(horizontal: false, vertical: true)

                let bodyText = banner.body(for: languageCode)
                if !bodyText.isEmpty {
                    Text(verbatim: bodyText)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss()
            } label: {
                AppSymbol.image("xmark")
                    .font(AppTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            // `.plain` avoids the sticky pressed/highlight chrome of `.borderless`.
            .buttonStyle(.plain)
            .accessibilityLabel(Bundle.currentLocalizedString("common.close"))
            .accessibilityIdentifier(AccessibilityIdentifiers.systemBannerDismiss)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.systemBanner)
    }
}
