//
//  RecipeDescriptionStyle.swift
//  RecipeScalerNative
//
//  Typography/colors for read-only description (aligned with web `.text-link`).
//

import SwiftUI
import UIKit

/// Typography context for description blocks — headings use the display font
/// at 1.1× body size to match the web CSS `[&_h1]:text-[1.1em]`.
enum RecipeDescriptionBlockTypography {
    case body
    case heading(level: Int)

    var baseFont: UIFont {
        switch self {
        case .body:
            return AppTypography.uiFont(AppFonts.sans, size: RecipeDescriptionStyle.bodyFontSize)
        case .heading:
            // Web: `[&_h1]:text-[1.1em]` — display font at 1.1× body size.
            return AppTypography.uiFont(AppFonts.display, size: RecipeDescriptionStyle.bodyFontSize * 1.1)
        }
    }

    var mediumFont: UIFont {
        switch self {
        case .body:
            return AppTypography.uiFont(AppFonts.sansMedium, size: RecipeDescriptionStyle.bodyFontSize, fallbackFamily: AppFonts.sansMedium)
        case .heading:
            // Headings already use display (extra-bold), keep same family/size for "strong".
            return AppTypography.uiFont(AppFonts.display, size: RecipeDescriptionStyle.bodyFontSize * 1.1)
        }
    }

    var italicFont: UIFont? {
        let size = fontSize
        let family: String = {
            switch self {
            case .body: return AppFonts.sans
            case .heading: return AppFonts.display
            }
        }()
        guard let descriptor = UIFont(name: family, size: size)?.fontDescriptor.withSymbolicTraits(.traitItalic) else {
            return nil
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    var fontSize: CGFloat {
        switch self {
        case .body:
            return RecipeDescriptionStyle.bodyFontSize
        case .heading:
            return RecipeDescriptionStyle.bodyFontSize * 1.1
        }
    }
}

enum RecipeDescriptionStyle {
    /// Web `--brand` used by `.text-link` (not recipe accent).
    static let linkColor = Color(red: 0, green: 114 / 255, blue: 245 / 255)
    static let linkUIColor = UIColor(red: 0, green: 114 / 255, blue: 245 / 255, alpha: 1)

    /// iOS Body — same as recipe list title and ingredient rows.
    static let bodyFontSize: CGFloat = AppTypography.bodySize
    static var bodyLineSpacing: CGFloat { bodyFontSize * 0.4 }

    static func bodyFont() -> UIFont {
        AppTypography.uiFont(AppFonts.sans, size: bodyFontSize)
    }

    static func mediumFont() -> UIFont {
        AppTypography.uiFont(AppFonts.sansMedium, size: bodyFontSize, fallbackFamily: AppFonts.sansMedium)
    }

    /// Read-only timer chip in description (web `.timer-reference`: `px-1`, `rounded-lg` → 8pt here).
    enum TimerHighlight {
        static let horizontalPadding: CGFloat = 4
        static let verticalPadding: CGFloat = 2
        static let cornerRadius: CGFloat = 8
        static let backgroundAlpha: CGFloat = 0.15
    }

    /// Inline chip: width from glyph bounds; height from font metrics (trim line-box slack below glyphs).
    static func timerHighlightRect(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        characterRange: NSRange,
        attributedText: NSAttributedString,
        contentOrigin: CGPoint
    ) -> CGRect {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let font = (attributedText.attribute(.font, at: characterRange.location, effectiveRange: nil) as? UIFont)
            ?? bodyFont()

        let vertical = TimerHighlight.verticalPadding
        let horizontal = TimerHighlight.horizontalPadding
        let inkHeight = font.ascender + abs(font.descender)

        return CGRect(
            x: glyphBounds.minX - horizontal + contentOrigin.x,
            y: glyphBounds.minY - vertical + contentOrigin.y,
            width: glyphBounds.width + horizontal * 2,
            height: inkHeight + vertical * 2
        )
    }

    /// Opaque fill matching timer chip (`accent` at `backgroundAlpha` over page background).
    static func timerHighlightSurfaceColor(accent: Color, colorScheme: ColorScheme) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let accentUIColor = UIColor(accent).resolvedColor(with: traits)
        let backgroundUIColor = UIColor.systemBackground.resolvedColor(with: traits)
        return Color(blend(
            accentUIColor,
            over: backgroundUIColor,
            fraction: TimerHighlight.backgroundAlpha
        ))
    }

    private static func blend(_ foreground: UIColor, over background: UIColor, fraction: CGFloat) -> UIColor {
        var fgR: CGFloat = 0, fgG: CGFloat = 0, fgB: CGFloat = 0, fgA: CGFloat = 0
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0, bgA: CGFloat = 0
        guard foreground.getRed(&fgR, green: &fgG, blue: &fgB, alpha: &fgA),
              background.getRed(&bgR, green: &bgG, blue: &bgB, alpha: &bgA)
        else {
            return background
        }
        let mix = min(max(fraction, 0), 1)
        let inverse = 1 - mix
        return UIColor(
            red: fgR * mix + bgR * inverse,
            green: fgG * mix + bgG * inverse,
            blue: fgB * mix + bgB * inverse,
            alpha: 1
        )
    }
}