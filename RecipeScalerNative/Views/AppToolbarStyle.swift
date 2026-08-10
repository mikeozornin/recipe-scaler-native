//
//  AppToolbarStyle.swift
//  RecipeScalerNative
//

import SwiftUI

/// Navigation bar actions: 16 pt body, accent tint.
enum AppToolbarStyle {
    static let iconSide: CGFloat = 20
    static let minimumTapSide: CGFloat = 44
    static let iconButtonPadding: CGFloat = (minimumTapSide - iconSide) / 2

    /// iOS 26 Liquid Glass toolbar pills hug label bounds; pre-26 toolbar chrome adds trailing inset.
    private static var labeledIconTrailingPadding: CGFloat {
        #if os(macOS)
        return 0
        #else
        if #available(iOS 26.0, *) {
            return iconButtonPadding
        }
        return 0
        #endif
    }

    @ViewBuilder
    static func icon(_ systemName: String) -> some View {
        #if os(macOS)
        AppSymbol.toolbarImage(systemName)
            .frame(width: iconSide, height: iconSide)
            .foregroundStyle(.primary)
        #else
        AppSymbol.toolbarImage(systemName)
            .resizable()
            .scaledToFit()
            .frame(width: iconSide, height: iconSide)
            .foregroundStyle(AppChromeAppearance.systemActionColor)
        #endif
    }

    @ViewBuilder
    static func actionText(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppTypography.body)
            .foregroundStyle(AppChromeAppearance.systemActionColor)
            .lineLimit(1)
    }

    @ViewBuilder
    static func labeledIcon(systemName: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            icon(systemName)
            actionText(title)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, iconButtonPadding)
        .padding(.trailing, labeledIconTrailingPadding)
        .frame(minHeight: minimumTapSide)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    static func iconOnly(systemName: String, isActive: Bool = false) -> some View {
        icon(systemName)
            .frame(width: minimumTapSide, height: minimumTapSide)
            .background(activeBackground(isActive))
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private static func activeBackground(_ isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
        }
    }
}

extension View {
    /// Text bar button (Cancel, Done, Import, …).
    func appToolbarTextButton() -> some View {
        font(AppTypography.body)
            .foregroundStyle(AppChromeAppearance.systemActionColor)
    }

    /// Alias for `appToolbarTextButton()` (confirmation actions).
    func appToolbarConfirmButton() -> some View {
        appToolbarTextButton()
    }

    /// Icon or custom label bar button.
    func appToolbarIconButton() -> some View {
        buttonStyle(.borderless)
    }
}
