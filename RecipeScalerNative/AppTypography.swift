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
    /// Decorative SF Symbol in `ContentUnavailableView` and other empty states.
    static let emptyStateIconSize: CGFloat = 48

    static let bodyLineSpacing: CGFloat = 4
    static let footnoteLineSpacing: CGFloat = 2

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

    static func sans(_ size: CGFloat) -> Font { Font(uiFont(AppFonts.sans, size: size)) }
    static func sansMedium(_ size: CGFloat) -> Font {
        Font(uiFont(AppFonts.sansMedium, size: size, fallbackFamily: AppFonts.sansMedium))
    }
    static func display(_ size: CGFloat) -> Font {
        Font(uiFont(AppFonts.display, size: size, fallbackFamily: AppFonts.display))
    }
    static func mono(_ size: CGFloat) -> Font { Font(uiFont(AppFonts.mono, size: size, fallbackFamily: AppFonts.mono)) }

    /// SF Symbol point size only — not for text labels.
    static func iconSize(_ points: CGFloat) -> Font { .system(size: points) }

    static func uiFont(
        _ name: String,
        size: CGFloat,
        fallbackFamily: String = AppFonts.sans
    ) -> UIFont {
        // Ensure bundled Martian faces are registered with CoreText before any lookup.
        // UIAppFonts registration from Info.plist is lazy and can race with the first
        // ContentView.body evaluation (.environment(\.font, AppTypography.body)).
        AppFonts.registerBundledFontsIfNeeded()

        func resolve(_ face: String) -> UIFont? {
            UIFont(name: face, size: size)
                ?? AppFonts.postScriptName(for: face).flatMap { UIFont(name: $0, size: size) }
        }

        return resolve(name)
            ?? resolve(fallbackFamily)
            ?? resolve(AppFonts.sans)
            ?? .systemFont(ofSize: size)
    }
}

extension View {
    /// Default text (16 pt Martian Grotesk) for List/Form and unstyled `Text`.
    func appListBodyTypography() -> some View {
        font(AppTypography.body)
    }

    /// Body size + line spacing for `TextField` and other controls that must match `.appBody()` height.
    func appBodyFieldTypography() -> some View {
        font(AppTypography.body)
            .lineSpacing(AppTypography.bodyLineSpacing)
    }
}

extension Text {
    func appBody() -> some View {
        self
            .font(AppTypography.body)
            .lineSpacing(AppTypography.bodyLineSpacing)
    }

    func appFootnote() -> some View {
        self
            .font(AppTypography.footnote)
            .lineSpacing(AppTypography.footnoteLineSpacing)
    }

    /// Semibold 16 pt body (headline) with standard body line spacing.
    func appHeadline() -> some View {
        self
            .font(AppTypography.headline)
            .lineSpacing(AppTypography.bodyLineSpacing)
    }

    /// Body typography that survives `.textSelection(.enabled)` (selection resets `.custom` fonts).
    func appBodySelectable(multilineTextAlignment: TextAlignment = .leading) -> some View {
        self
            .foregroundStyle(.primary)
            .multilineTextAlignment(multilineTextAlignment)
            .textSelection(.enabled)
            .font(Font(AppTypography.bodyUIFont))
            .lineSpacing(AppTypography.bodyLineSpacing)
    }
}

/// List/Form section title. iOS < 26 uses iOS Settings legacy (footnote, ALL CAPS, tracking 0.8);
/// iOS 26+ matches Apple Settings/Notes (title case, no tracking).
struct AppSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(AppTypography.footnote)
            .foregroundStyle(Color(.secondaryLabel))
            .tracking(Self.usesUpperCase ? AppSectionHeader.letterSpacing : 0)
            .textCase(Self.usesUpperCase ? .uppercase : nil)
    }

    /// ~0.06 em at 13 pt (web section label rhythm, legacy ALL CAPS only).
    static let letterSpacing: CGFloat = 0.8

    /// iOS 26+ renders section headers in title case (Apple Settings/Notes style).
    /// iOS < 26 keeps legacy ALL CAPS + tracking 0.8. Single `#available` source of truth
    /// for section header casing — view-файлы используют этот token, а не свой `#available`.
    static var usesUpperCase: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }
}

extension View {
    /// Keeps `AppSectionHeader` footnote + secondary color in insetGrouped `Section` headers.
    func appListSectionHeaderStyle() -> some View {
        headerProminence(.standard)
    }
}

/// Invisible section header placeholder — keeps spacing above a headerless list group.
struct AppSectionHeaderSpacer: View {
    var body: some View {
        Text(verbatim: " ")
            .font(AppTypography.footnote)
            .tracking(AppSectionHeader.usesUpperCase ? AppSectionHeader.letterSpacing : 0)
            .textCase(AppSectionHeader.usesUpperCase ? .uppercase : nil)
            .accessibilityHidden(true)
            .opacity(0)
    }
}

enum AppChromeAppearance {
    static func configure() {
        configureNavigationBar()
        configureBarButtonItems()
        configureTabBar()
        configureListSectionHeaders()
        configureTextInputs()
        configureSegmentedControl()
        configureAlerts()
    }

    /// UIKit action tint for system chrome (navbar back/edit/share/done, standalone UIBarButtonItem titles).
    /// iOS < 26 → app accent (legacy blue). iOS 26+ → nil, so system chrome renders neutral
    /// (matching iOS 26 Calendar). Single `#available` source of truth for UIKit chrome.
    static var systemActionUIColor: UIColor? {
        if #available(iOS 26.0, *) { return nil }
        return UIColor(Color.accentColor)
    }

    /// SwiftUI action tint. Same policy as `systemActionUIColor`; on iOS 26+ resolves to
    /// `.label` (adaptive black/white) instead of accent. Single `#available` source of truth
    /// for SwiftUI toolbar buttons.
    static var systemActionColor: Color {
        if #available(iOS 26.0, *) { return Color(UIColor.label) }
        return Color.accentColor
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

        var actionButtonAttributes: [NSAttributedString.Key: Any] = [
            .font: AppTypography.bodyUIFont,
        ]
        if let tint = systemActionUIColor {
            actionButtonAttributes[.foregroundColor] = tint
        }
        appearance.backButtonAppearance.normal.titleTextAttributes = actionButtonAttributes
        appearance.buttonAppearance.normal.titleTextAttributes = actionButtonAttributes
        appearance.doneButtonAppearance.normal.titleTextAttributes = actionButtonAttributes

        let navBar = UINavigationBar.appearance()
        if let tint = systemActionUIColor {
            navBar.tintColor = tint
        }
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.compactScrollEdgeAppearance = appearance
        // Remove bottom padding inside the large title row.
        // UINavigationBar.layoutMargins.bottom (default ~8pt) creates the space
        // between the title text baseline and the nav bar's bottom edge.
    }

    private static func configureBarButtonItems() {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: AppTypography.bodyUIFont,
        ]
        if let tint = systemActionUIColor {
            attributes[.foregroundColor] = tint
        }
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
        let headerLabel = UILabel.appearance(
            whenContainedInInstancesOf: [UITableViewHeaderFooterView.self]
        )
        headerLabel.font = headerFont
        headerLabel.textColor = .secondaryLabel
    }

    private static func configureTextInputs() {
        UITextField.appearance().font = AppTypography.bodyUIFont
        // Do not set UITextView.appearance().font — it rewrites per-run fonts in read-only
        // attributed text (recipe description). Editable views set .font explicitly
        // (e.g. GrowingTitleTextView in RecipeTitleTextField).
    }

    private static func configureSegmentedControl() {
        let attributes: [NSAttributedString.Key: Any] = [.font: AppTypography.bodyUIFont]
        UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .selected)
    }

    private static func configureAlerts() {
        UILabel.appearance(whenContainedInInstancesOf: [UIAlertController.self]).font =
            AppTypography.bodyUIFont
    }
}