//
//  WidgetFonts.swift
//  HomeWidgetExtension
//
//  Spec 030 — font helpers for the widget.
//
//  Mirrors the project's Martian typefaces. Fonts are bundled via the
//  extension's Info.plist `UIAppFonts` array.
//

import SwiftUI
import UIKit

enum WidgetFonts {
    static let sans = "Martian Grotesk Nr Lt"
    static let sansMedium = "Martian Grotesk Nr Md"
    static let mono = "Martian Mono Nr Lt"
    /// Figma timer digit tracking (−0.1); mirrored in `WidgetTimerLayout.tracking`.
    static let timerTracking: CGFloat = -0.1

    static func sansFont(size: CGFloat) -> Font {
        .custom(sans, size: size)
    }

    static func sansMediumFont(size: CGFloat) -> Font {
        .custom(sansMedium, size: size)
    }

    static func monoFont(size: CGFloat) -> Font {
        .custom(mono, size: size).monospacedDigit()
    }

    static var linearNameUIFont: UIFont {
        UIFont(name: sans, size: WidgetTimerLayout.linearNameSize)
            ?? .systemFont(ofSize: WidgetTimerLayout.linearNameSize, weight: .light)
    }

    /// Recipe/step label with Figma metrics: 15pt / 18pt line height / −0.1 tracking.
    static func recipeNameAttributedString(_ string: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = WidgetTimerLayout.linearNameLineHeight
        paragraph.maximumLineHeight = WidgetTimerLayout.linearNameLineHeight
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: linearNameUIFont,
            .kern: timerTracking,
            .paragraphStyle: paragraph,
        ]
        return NSAttributedString(string: string, attributes: attributes)
    }

    static func recipeNameText(_ string: String) -> Text {
        Text(AttributedString(recipeNameAttributedString(string)))
    }
}

extension Text {
    /// Martian Grotesk Light — keeps `Text` type for multiline layout in widgets.
    func widgetSans(_ size: CGFloat) -> Text {
        font(WidgetFonts.sansFont(size: size))
    }

    func widgetSansMedium(_ size: CGFloat) -> Text {
        font(WidgetFonts.sansMediumFont(size: size))
    }

    func widgetMono(_ size: CGFloat) -> Text {
        font(WidgetFonts.monoFont(size: size))
    }

    /// Figma timer digit tracking (−0.1).
    func widgetTimerTracking() -> Text {
        tracking(WidgetFonts.timerTracking)
    }
}

extension View {
    /// Martian Grotesk Light at the given size.
    func widgetSans(_ size: CGFloat) -> some View {
        font(WidgetFonts.sansFont(size: size))
    }

    /// Martian Grotesk Medium at the given size.
    func widgetSansMedium(_ size: CGFloat) -> some View {
        font(WidgetFonts.sansMediumFont(size: size))
    }

    /// Martian Mono Light at the given size, with monospaced digits for stable countdowns.
    func widgetMono(_ size: CGFloat) -> some View {
        font(WidgetFonts.monoFont(size: size))
    }

    /// Figma timer digit tracking (−0.1).
    func widgetTimerTracking() -> some View {
        tracking(WidgetFonts.timerTracking)
    }
}
