//
//  AdaptiveColumnWidthModifier.swift
//  RecipeScalerNative
//
//  Spec 063 — iPad column width caps. Keeps long-form content (Profile,
//  recipe detail, public recipe) centered and readable on `.regular`
//  horizontal size class. On `.compact` (iPhone) it is a no-op so the
//  existing full-width layouts stay intact.
//

import SwiftUI

/// Maximum column width for Profile/Account on iPad. Aligned with Apple HIG
/// grouped-list convention (~700pt) — wider feels stranded, narrower wastes
/// space.
enum AccountColumnLayout {
    static let maxWidth: CGFloat = 700
}

/// Maximum column width for recipe detail content (private + public).
/// Slightly wider than Account because of ingredient grid + image, but still
/// capped so hero and body text don't stretch across the whole iPad column.
enum RecipeDetailColumnLayout {
    static let maxWidth: CGFloat = 800
}

private struct AdaptiveColumnWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// Centers the receiver inside an adaptive column of at most `maxWidth`
    /// points on iPad (`.regular` size class). On iPhone (`.compact`) it is
    /// a no-op, preserving existing layouts.
    ///
    /// Use on the root view of any detail screen whose content (List,
    /// ScrollView, Form) should not stretch across the whole iPad column.
    func adaptiveColumn(maxWidth: CGFloat) -> some View {
        modifier(AdaptiveColumnWidthModifier(maxWidth: maxWidth))
    }

    /// Profile/Account column cap (~700pt). See `AccountColumnLayout`.
    var accountColumnWidth: some View {
        adaptiveColumn(maxWidth: AccountColumnLayout.maxWidth)
    }

    /// Recipe detail column cap (~800pt). See `RecipeDetailColumnLayout`.
    var recipeDetailColumnWidth: some View {
        adaptiveColumn(maxWidth: RecipeDetailColumnLayout.maxWidth)
    }
}
