import UIKit

/// Shared list row box model (recipe list + ingredient rows).
enum RecipeRowLayoutMetrics {
    /// Matches web `px-4` and recipe `listRowInsets.leading`.
    static let listHorizontalInset: CGFloat = 16
    static let rowHeight: CGFloat = 44
    static let titleFontSize: CGFloat = 16
    static let wrappedLineSpacing: CGFloat = 4
    static let rowMarkerSpacing: CGFloat = 12
    /// Leading slot: color dot, emoji, row number, or «+».
    static let markerSlotWidth: CGFloat = 22
    /// Trailing quantity column (web ingredient grid).
    static let amountColumnWidth: CGFloat = 72

    /// Bottom inset below the KBJU line inside an ingredient edit row.
    static let nutritionLineBottomInset: CGFloat = 4

    static var titleUIFont: UIFont {
        UIFont(name: AppFonts.sans, size: titleFontSize)
            ?? UIFont.systemFont(ofSize: titleFontSize)
    }

    static var titleLineHeight: CGFloat {
        ceil(titleUIFont.lineHeight)
    }

    /// Centers a single 16 pt line inside a 44 pt row.
    static var rowVerticalPadding: CGFloat {
        max(0, (rowHeight - titleLineHeight) / 2)
    }

    static var listRowInsets: EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: listHorizontalInset,
            bottom: 0,
            trailing: listHorizontalInset
        )
    }
}

import SwiftUI

extension View {
    /// Primary list row chrome: 44 pt min height, symmetric vertical padding.
    func ingredientListRowChrome() -> some View {
        padding(.vertical, RecipeRowLayoutMetrics.rowVerticalPadding)
            .frame(minHeight: RecipeRowLayoutMetrics.rowHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Edit row with name + KBJU: tighter vertical rhythm, 4 pt below KBJU.
    func ingredientListRowChromeCompact() -> some View {
        padding(.top, 4)
            .padding(.bottom, RecipeRowLayoutMetrics.nutritionLineBottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IngredientEditRowChrome: ViewModifier {
    let showsNutritionLine: Bool

    func body(content: Content) -> some View {
        if showsNutritionLine {
            content.ingredientListRowChromeCompact()
        } else {
            content.ingredientListRowChrome()
        }
    }
}