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

    private struct ToolbarIconMetrics {
        let width: CGFloat
        let height: CGFloat
        let pointSize: CGFloat
    }

    /// Wide glyphs (e.g. bell + sound waves) need a larger point size so the
    /// core icon matches `iconSide` after `scaledToFit`.
    private static func toolbarIconMetrics(for systemName: String) -> ToolbarIconMetrics {
        switch systemName {
        case "bell.and.waves.left.and.right.fill":
            return ToolbarIconMetrics(width: 28, height: iconSide, pointSize: 26)
        default:
            return ToolbarIconMetrics(width: iconSide, height: iconSide, pointSize: iconSide)
        }
    }

    /// iOS 26 Liquid Glass toolbar pills hug label bounds; pre-26 toolbar chrome adds trailing inset.
    private static var labeledIconTrailingPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return iconButtonPadding
        }
        return 0
    }

    @ViewBuilder
    static func icon(_ systemName: String) -> some View {
        let metrics = toolbarIconMetrics(for: systemName)
        AppSymbol.sizedImage(systemName, pointSize: metrics.pointSize, weight: .semibold)
            .resizable()
            .scaledToFit()
            .frame(width: metrics.width, height: metrics.height)
            .foregroundStyle(AppChromeAppearance.systemActionColor)
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
        labeledIconRow(systemName: systemName, title: title, showsChevron: false)
    }

    /// Toolbar menu trigger: icon + body label + chevron (web follow dropdown parity).
    @ViewBuilder
    static func dropdownLabel(systemName: String, title: LocalizedStringKey) -> some View {
        labeledIconRow(systemName: systemName, title: title, showsChevron: true)
    }

    @ViewBuilder
    private static func labeledIconRow(
        systemName: String,
        title: LocalizedStringKey,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 4) {
            icon(systemName)
            actionText(title)
            if showsChevron {
                icon("chevron.down")
            }
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