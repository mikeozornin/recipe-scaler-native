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
    /// Recipe list trailing preview (web 44×44 `object-cover`).
    static let recipeListThumbnailSide: CGFloat = 44
    /// Recipe list title, ingredient name/amount (`AppTypography.body`).
    static let titleFontSize: CGFloat = AppTypography.bodySize
    static let ingredientBodyFontSize: CGFloat = AppTypography.bodySize
    static var wrappedLineSpacing: CGFloat { AppTypography.bodyLineSpacing }
    /// Gap between row number and ingredient name (web `mr-2` ≈ 8pt; half of prior 12pt grid).
    static let rowMarkerSpacing: CGFloat = 6
    /// Tighter gap between marker and ingredient name (recipe detail, list of ingredients).
    static let ingredientMarkerSpacing: CGFloat = 2
    /// Gap between the ingredients block (marker + name) and qty columns.
    static let gridIngredientsToQtySpacing: CGFloat = 8
    /// Gap between base and scaled qty.
    static let gridQtyColumnsSpacing: CGFloat = 4
    /// Name → KBJU line (view and edit).
    static let nutritionLineSpacing: CGFloat = 4
    /// Recipe list search snippet directly under the title (web: stacked in one column).
    static let searchSnippetSpacing: CGFloat = 2

    /// Leading slot: row number / «+» — tight to body digit width.
    static var markerSlotWidth: CGFloat {
        let font = AppTypography.uiFont(AppFonts.sans, size: ingredientBodyFontSize)
        let width = ("99" as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) - 2
    }

    /// Base (non-scaled) qty column — header «Qty» and black amounts align here.
    static var baseQtyColumnWidth: CGFloat {
        monoTextWidth(sample: "280.8", trailingPadding: 2)
    }

    /// Scaled qty column (accent preview / view-mode edit).
    static var scaledQtyColumnMinWidth: CGFloat {
        monoTextWidth(sample: "280.8", trailingPadding: 2)
    }

    static var originalQtyColumnWidth: CGFloat { baseQtyColumnWidth }
    static var scaledQtyColumnWidth: CGFloat { scaledQtyColumnMinWidth }
    static var qtyColumnMinWidth: CGFloat { baseQtyColumnWidth }

    /// Trailing inset for `List` rows — room for ≡ only (not a layout column).
    static let listReorderTrailingInset: CGFloat = 20
    static let listReorderColumnWidth: CGFloat = listReorderTrailingInset

    private static func monoTextWidth(sample: String, trailingPadding: CGFloat) -> CGFloat {
        let font = AppTypography.uiFont(AppFonts.mono, size: AppTypography.bodySize)
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) + trailingPadding
    }
    /// Legacy drag column width — same as list reorder for header alignment.
    static let dragHandleColumnWidth: CGFloat = listReorderColumnWidth

    static var qtyColumnsWidth: CGFloat {
        originalQtyColumnWidth + scaledQtyColumnWidth
    }

    /// Legacy single-column width — prefer `originalQtyColumnWidth` + `scaledQtyColumnWidth`.
    static let amountColumnWidth: CGFloat = qtyColumnsWidth

    /// Bottom inset below the KBJU line inside an ingredient edit row.
    static let nutritionLineBottomInset: CGFloat = 4

    static var footnoteLineHeight: CGFloat {
        ceil(AppTypography.uiFont(AppFonts.sans, size: AppTypography.footnoteSize).lineHeight)
    }

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

// MARK: - Edit grid layout (List reorder column consumes trailing width)

private struct IngredientGridContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Row content width inside edit `List` (section width minus system reorder control).
    var ingredientGridContentWidth: CGFloat? {
        get { self[IngredientGridContentWidthKey.self] }
        set { self[IngredientGridContentWidthKey.self] = newValue }
    }
}

struct IngredientSectionWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct IngredientEditRowHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

extension View {
    func ingredientGridContentWidth(_ width: CGFloat?) -> some View {
        environment(\.ingredientGridContentWidth, width)
    }

    func reportIngredientEditRowHeight(rowId: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: IngredientEditRowHeightKey.self,
                    value: [rowId: proxy.size.height]
                )
            }
        }
    }

    /// Keeps name/qty columns aligned with view mode; edit `List` steals trailing width for reorder.
    func ingredientGridContentWidthConstrained() -> some View {
        modifier(IngredientGridContentWidthConstraintModifier())
    }

}

private struct IngredientGridContentWidthConstraintModifier: ViewModifier {
    @Environment(\.ingredientGridContentWidth) private var contentWidth

    func body(content: Content) -> some View {
        if let contentWidth {
            content.frame(width: contentWidth, alignment: .leading)
        } else {
            content
        }
    }
}

extension View {
    /// Primary list row chrome: 44 pt min height, symmetric vertical padding.
    func ingredientListRowChrome() -> some View {
        padding(.vertical, RecipeRowLayoutMetrics.ingredientRowVerticalPadding)
            .frame(minHeight: RecipeRowLayoutMetrics.rowHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// Top separator between ingredient list rows (web `divide-y`).
struct IngredientListRowSeparator: View {
    var body: some View {
        Divider()
    }
}