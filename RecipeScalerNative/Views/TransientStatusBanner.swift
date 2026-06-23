//
//  TransientStatusBanner.swift
//  RecipeScalerNative
//

import SwiftUI

/// Short-lived non-modal feedback (e.g. items added to shopping list).
struct TransientStatusBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: String

    /// Matches swipe «add to shopping» actions (`.tint(.green)`).
    private var bannerFill: Color { .green }

    var body: some View {
        if #available(iOS 26.0, *) {
            glassPillBody
        } else {
            legacyBarBody
        }
    }

    @ViewBuilder
    private func bannerContent(compact: Bool) -> some View {
        HStack(alignment: compact ? .center : .top, spacing: 10) {
            AppSymbol.image("cart.badge.plus")
                .font(AppTypography.iconSize(AppTypography.bodySize))
            if compact {
                Text(message)
                    .font(AppTypography.subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityIdentifiers.transientStatusMessage)
            } else {
                Text(message)
                    .font(AppTypography.subheadline)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityIdentifiers.transientStatusMessage)
            }
        }
    }

    @available(iOS 26.0, *)
    private var glassPillBody: some View {
        bannerContent(compact: true)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(.green), in: .capsule)
            .accessibilityIdentifier(AccessibilityIdentifiers.transientStatusBanner)
    }

    private var legacyBarBody: some View {
        bannerContent(compact: false)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bannerFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 10, y: 4)
            .padding(.horizontal, 12)
            .accessibilityIdentifier(AccessibilityIdentifiers.transientStatusBanner)
    }
}
