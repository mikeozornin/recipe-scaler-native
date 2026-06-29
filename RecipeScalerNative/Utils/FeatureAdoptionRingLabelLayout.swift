//
//  FeatureAdoptionRingLabelLayout.swift
//  RecipeScalerNative
//
//  Spec 038 — progress-ring label width + font sizing (stable per total/locale).
//

import UIKit

enum FeatureAdoptionRingLabelLayout {
    static let diameter: CGFloat = 152
    static let strokeWidth: CGFloat = 12
    static let labelHorizontalInset: CGFloat = 12
    static let baseLabelFontSize: CGFloat = 40
    static let minimumLabelFontSize: CGFloat = 20
    static let absoluteMinimumLabelFontSize: CGFloat = 14
    /// Monospaced digits in SwiftUI can be slightly wider than proportional UIKit measurement.
    static let measurementWidthSafetyMargin: CGFloat = 4

    static var labelMaxWidth: CGFloat {
        let innerDiameter = diameter - 2 * strokeWidth
        return innerDiameter - 2 * labelHorizontalInset
    }

    private static var fontSizeCache: [String: CGFloat] = [:]

    static func cachedFontSize(for text: String, localeIdentifier: String) -> CGFloat {
        let cacheKey = "\(localeIdentifier)|\(text)"
        if let cached = fontSizeCache[cacheKey] {
            return cached
        }
        let fitted = fittingLabelFontSize(
            for: text,
            maxWidth: labelMaxWidth - measurementWidthSafetyMargin
        )
        fontSizeCache[cacheKey] = fitted
        return fitted
    }

    static func fittingLabelFontSize(
        for text: String,
        maxWidth: CGFloat,
        baseSize: CGFloat = baseLabelFontSize,
        minimumSize: CGFloat = minimumLabelFontSize
    ) -> CGFloat {
        var size = baseSize
        while size >= absoluteMinimumLabelFontSize {
            let font = AppTypography.uiFont(AppFonts.sansMedium, size: size, fallbackFamily: AppFonts.sansMedium)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            if width <= maxWidth {
                return size
            }
            size -= 1
        }
        return absoluteMinimumLabelFontSize
    }
}
