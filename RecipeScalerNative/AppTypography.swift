//
//  AppTypography.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

/// Martian text styles aligned with iOS Dynamic Type default metrics (Large).
enum AppTypography {
    static let bodySize: CGFloat = 16
    static let subheadlineSize: CGFloat = 15
    static let footnoteSize: CGFloat = 13
    static let compactSize: CGFloat = 14
    static let calloutSize: CGFloat = 16
    static let title3Size: CGFloat = 20
    static let title2Size: CGFloat = 22
    static let recipeTitleSize: CGFloat = 28
    static let authTitleSize: CGFloat = 30
    static let splashTitleSize: CGFloat = 24
    static let tabBarSize: CGFloat = 10

    static var body: Font { sans(bodySize) }
    static var subheadline: Font { sans(subheadlineSize) }
    static var footnote: Font { sans(footnoteSize) }
    static var compact: Font { sans(compactSize) }
    static var callout: Font { sans(calloutSize) }
    static var headline: Font { sansMedium(bodySize) }
    static var title3: Font { sansMedium(title3Size) }
    static var title2: Font { display(title2Size) }
    static var tabBar: Font { sans(tabBarSize) }

    static var bodySemibold: Font { sansMedium(bodySize) }
    static var subheadlineSemibold: Font { sansMedium(subheadlineSize) }
    static var footnoteSemibold: Font { sansMedium(footnoteSize) }
    static var monoFootnoteDigits: Font { mono(footnoteSize).monospacedDigit() }

    static var bodyUIFont: UIFont { uiFont(AppFonts.sans, size: bodySize) }
    static var sansMediumBodyUIFont: UIFont { uiFont(AppFonts.sansMedium, size: bodySize) }
    static var displayLargeTitleUIFont: UIFont { uiFont(AppFonts.display, size: 34) }
    static var tabBarUIFont: UIFont { uiFont(AppFonts.sans, size: tabBarSize) }
    static var footnoteUIFont: UIFont { uiFont(AppFonts.sans, size: footnoteSize) }

    static func sans(_ size: CGFloat) -> Font { .custom(AppFonts.sans, size: size) }
    static func sansMedium(_ size: CGFloat) -> Font { .custom(AppFonts.sansMedium, size: size) }
    static func display(_ size: CGFloat) -> Font { .custom(AppFonts.display, size: size) }
    static func mono(_ size: CGFloat) -> Font { .custom(AppFonts.mono, size: size) }

    /// SF Symbol point size only — not for text labels.
    static func iconSize(_ points: CGFloat) -> Font { .system(size: points) }

    static func uiFont(
        _ name: String,
        size: CGFloat,
        fallbackFamily: String = AppFonts.sans
    ) -> UIFont {
        UIFont(name: name, size: size)
            ?? UIFont(name: fallbackFamily, size: size)
            ?? UIFont(name: AppFonts.sans, size: size)!
    }
}

extension View {
    /// Default text (16 pt Martian Grotesk) for List/Form and unstyled `Text`.
    func appListBodyTypography() -> some View {
        font(AppTypography.body)
    }
}

/// List/Form section title (iOS Settings style: footnote, caps, tracking).
struct AppSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    init(_ title: String) {
        self.title = LocalizedStringKey(title)
    }

    var body: some View {
        Text(title)
            .font(AppTypography.footnote)
            .foregroundStyle(.secondary)
            .tracking(AppSectionHeader.letterSpacing)
            .textCase(.uppercase)
    }

    /// ~0.06 em at 13 pt (web section label rhythm).
    static let letterSpacing: CGFloat = 0.8
}

enum AppChromeAppearance {
    static func configure() {
        configureNavigationBar()
        configureBarButtonItems()
        configureTabBar()
        configureListSectionHeaders()
        configureTextInputs()
        configureSegmentedControl()
    }

    private static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [
            .font: AppTypography.sansMediumBodyUIFont,
            .foregroundColor: UIColor.label,
        ]
        appearance.largeTitleTextAttributes = [
            .font: AppTypography.displayLargeTitleUIFont,
            .foregroundColor: UIColor.label,
        ]

        let actionButtonAttributes: [NSAttributedString.Key: Any] = [
            .font: AppTypography.bodyUIFont,
            .foregroundColor: UIColor(Color.accentColor),
        ]
        appearance.backButtonAppearance.normal.titleTextAttributes = actionButtonAttributes
        appearance.buttonAppearance.normal.titleTextAttributes = actionButtonAttributes
        appearance.doneButtonAppearance.normal.titleTextAttributes = actionButtonAttributes

        let navBar = UINavigationBar.appearance()
        navBar.tintColor = UIColor(Color.accentColor)
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.compactScrollEdgeAppearance = appearance
    }

    private static func configureBarButtonItems() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: AppTypography.bodyUIFont,
            .foregroundColor: UIColor(Color.accentColor),
        ]
        UIBarButtonItem.appearance().setTitleTextAttributes(attributes, for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes(attributes, for: .highlighted)
    }

    private static func configureTabBar() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: AppTypography.tabBarUIFont,
        ]
        UITabBarItem.appearance().setTitleTextAttributes(attributes, for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes(attributes, for: .selected)
    }

    private static func configureListSectionHeaders() {
        let headerFont = AppTypography.uiFont(AppFonts.sans, size: AppTypography.footnoteSize)
        UILabel.appearance(
            whenContainedInInstancesOf: [UITableViewHeaderFooterView.self]
        ).font = headerFont
    }

    private static func configureTextInputs() {
        UITextField.appearance().font = AppTypography.bodyUIFont
        UITextView.appearance().font = AppTypography.bodyUIFont
    }

    private static func configureSegmentedControl() {
        let attributes: [NSAttributedString.Key: Any] = [.font: AppTypography.bodyUIFont]
        UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .selected)
    }
}