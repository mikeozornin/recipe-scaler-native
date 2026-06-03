//
//  AppToolbarStyle.swift
//  RecipeScalerNative
//

import SwiftUI

/// Navigation bar actions: 17 pt body, accent tint.
enum AppToolbarStyle {
    static let iconSide: CGFloat = 20
    static let minimumTapSide: CGFloat = 44
    static let iconButtonPadding: CGFloat = (minimumTapSide - iconSide) / 2

    @ViewBuilder
    static func icon(_ systemName: String) -> some View {
        AppSymbol.toolbarImage(systemName)
            .resizable()
            .scaledToFit()
            .frame(width: iconSide, height: iconSide)
            .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    static func icon(_ symbol: RecipeSymbol) -> some View {
        symbol.toolbarImage()
            .resizable()
            .scaledToFit()
            .frame(width: iconSide, height: iconSide)
            .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    static func actionText(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.body)
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
    }

    @ViewBuilder
    static func labeledIcon(systemName: String, title: String) -> some View {
        HStack(spacing: 4) {
            icon(systemName)
            actionText(title)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, iconButtonPadding)
        .padding(.trailing, 0)
        .frame(minHeight: minimumTapSide)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    static func labeledIcon(_ symbol: RecipeSymbol, title: String) -> some View {
        HStack(spacing: 4) {
            icon(symbol)
            actionText(title)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, iconButtonPadding)
        .padding(.trailing, 0)
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
    static func iconOnly(_ symbol: RecipeSymbol, isActive: Bool = false) -> some View {
        icon(symbol)
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
            .foregroundStyle(Color.accentColor)
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