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
        HStack(alignment: .top, spacing: 10) {
            AppSymbol.image("cart.badge.plus")
                .font(AppTypography.iconSize(AppTypography.bodySize))
            Text(message)
                .font(AppTypography.subheadline)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(AccessibilityIdentifiers.transientStatusMessage)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bannerFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .accessibilityIdentifier(AccessibilityIdentifiers.transientStatusBanner)
    }
}