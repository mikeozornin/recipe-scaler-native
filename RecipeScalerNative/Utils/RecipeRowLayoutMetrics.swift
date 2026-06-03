import UIKit

/// Recipe detail header: hero image and title spacing (web `px-4` under nav / below image).
enum RecipeDetailLayoutMetrics {
    /// Top inset before the title block when there is no image; same gap between hero image and title.
    static let titleTopSpacing: CGFloat = RecipeRowLayoutMetrics.listHorizontalInset
}

/// Shared list row box model (recipe list + ingredient rows).
enum RecipeRowLayoutMetrics {
    /// Matches web `px-4` and recipe `listRowInsets.leading`.
    static let listHorizontalInset: CGFloat = 16
    static let rowHeight: CGFloat = 44
    /// Recipe list title, ingredient name/amount (`AppTypography.body`).
    static let titleFontSize: CGFloat = AppTypography.bodySize
    static let ingredientBodyFontSize: CGFloat = AppTypography.bodySize
    static let wrappedLineSpacing: CGFloat = 4
    static let rowMarkerSpacing: CGFloat = 12
    /// Leading slot: color dot, emoji, row number, or «+».
    static let markerSlotWidth: CGFloat = 22
    /// Trailing quantity column (web ingredient grid).
    static let amountColumnWidth: CGFloat = 72

    /// Bottom inset below the KBJU line inside an ingredient edit row.
    static let nutritionLineBottomInset: CGFloat = 4

    static var titleUIFont: UIFont {
        AppTypography.uiFont(AppFonts.sans, size: titleFontSize)
    }

    static var titleLineHeight: CGFloat {
        ceil(titleUIFont.lineHeight)
    }

    static var ingredientBodyUIFont: UIFont {
        AppTypography.uiFont(AppFonts.sans, size: ingredientBodyFontSize)
    }

    static var ingredientBodyLineHeight: CGFloat {
        ceil(ingredientBodyUIFont.lineHeight)
    }

    /// Centers a single body line inside a 44 pt row.
    static var rowVerticalPadding: CGFloat {
        max(0, (rowHeight - titleLineHeight) / 2)
    }

    /// Centers ingredient row text (body) inside a 44 pt row.
    static var ingredientRowVerticalPadding: CGFloat {
        max(0, (rowHeight - ingredientBodyLineHeight) / 2)
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
        padding(.vertical, RecipeRowLayoutMetrics.ingredientRowVerticalPadding)
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

/// Top separator between ingredient list rows (web `divide-y`).
struct IngredientListRowSeparator: View {
    var body: some View {
        Divider()
    }
}