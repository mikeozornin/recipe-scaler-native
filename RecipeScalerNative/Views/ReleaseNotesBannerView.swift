//
//  ReleaseNotesBannerView.swift
//  RecipeScalerNative
//
//  Spec 077 — dismissible in-app updates card. Visual template: SystemBannerView (061).
//

import SwiftUI

struct ReleaseNotesBannerView: View {
    let title: String
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("release-notes.banner.label")
                    .appFootnote()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: title)
                    .appHeadline()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("release-notes.banner.open"))
            .accessibilityIdentifier(AccessibilityIdentifiers.releaseNotesBannerOpen)

            Button(action: onDismiss) {
                AppSymbol.image("xmark")
                    .font(AppTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("release-notes.banner.dismiss"))
            .accessibilityIdentifier(AccessibilityIdentifiers.releaseNotesBannerDismiss)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.releaseNotesBanner)
    }
}
