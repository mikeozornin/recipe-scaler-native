//
//  RecipeDescriptionStyle.swift
//  RecipeScalerNative
//
//  Typography/colors for read-only description (aligned with web `.text-link`).
//

import SwiftUI
import UIKit

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
}