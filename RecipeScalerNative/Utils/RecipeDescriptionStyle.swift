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

    static let bodyFontSize: CGFloat = 17
    static var bodyLineSpacing: CGFloat { bodyFontSize * 0.4 }

    static func bodyFont() -> UIFont {
        UIFont(name: AppFonts.sans, size: bodyFontSize) ?? .systemFont(ofSize: bodyFontSize)
    }

    static func mediumFont() -> UIFont {
        UIFont(name: AppFonts.sansMedium, size: bodyFontSize) ?? .boldSystemFont(ofSize: bodyFontSize)
    }
}