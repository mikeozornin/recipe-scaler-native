import SwiftUI

enum ProcessTableLayout {
    static let stepsHeaderToCtaGap: CGFloat = 8
    static let ctaMinHit: CGFloat = 44
    static let matrixPadding: CGFloat = 16
    static let cookingHorizontalEdgePad: CGFloat = 8
    /// Trailing inset on the Dynamic Island edge. 0 so gray matrix reaches the
    /// physical edge; Close still uses `cookingCloseTrailingPad`.
    static let cookingTrailingEdgePad: CGFloat = 0
    /// Leading inset (home indicator): trailing pad plus 16 pt extra clearance.
    static let cookingLeadingEdgePad: CGFloat = cookingHorizontalEdgePad + 16
    /// Top inset of cooking content (title).
    static let cookingContentTopPad: CGFloat = 16
    /// Close: 28 pt from the island edge, 10 pt from the top.
    static let cookingCloseTrailingPad: CGFloat = 28
    static let cookingCloseTopPad: CGFloat = 10
    static let prepRowSpacing: CGFloat = 8
    static let prepStackToGridGap: CGFloat = 0
    /// Vertical inset around the prep stack (top of scroll + gap to grid).
    static let prepVerticalPad: CGFloat = 8
    static let ingredientColumnFraction: CGFloat = 0.25
    static let ingredientColumnTrailingPad: CGFloat = 12
    /// Floor for the sticky column: checkbox + thumb + readable name even when
    /// 25 % of the visible matrix is too narrow (portrait fallback, SE).
    static let ingredientColumnMinWidth: CGFloat = 192
    static let rowCheckboxVisualWidth: CGFloat = 24
    /// Same raster size as the shopping / ingredients-list marker (`AppTypography.bodySize`).
    static let checkboxPointSize: CGFloat = AppTypography.bodySize
    static let rowMinHeight: CGFloat = 44
    static let timerHeaderMinHeight: CGFloat = 36
    static let cookColumnMinWidth: CGFloat = 112
    static let cellTextHorizontalPad: CGFloat = 10
    static let cellTextVerticalPad: CGFloat = 4
    /// Vertical pad of the sticky ingredient row (4 pt cell pad + 2 pt leftover after −6).
    static let ingredientRowVerticalPad: CGFloat = cellTextVerticalPad + 2
    static let cellCheckboxInset: CGFloat = 4
    static let rowCheckboxToThumbGap: CGFloat = 8
    static let illustrationSlot: CGFloat = 40
    static let timerChipGap: CGFloat = 4
    static let timerChipHorizontalPad: CGFloat = 8
    static let timerChipVerticalPad: CGFloat = 6
    static let leftoverBarPadding: CGFloat = 12
    static let bannerSpacing: CGFloat = 8
    /// Footnote cap height of the stale row (nutrition parity). The rebuild
    /// control still has a 44 pt hit; negative padding keeps this as the row height.
    static var bannerLineHeight: CGFloat {
        ceil(AppTypography.footnoteUIFont.lineHeight)
    }
    static var bannerHitVerticalCollapse: CGFloat {
        -(ctaMinHit - bannerLineHeight) / 2
    }
    /// Gap between the compact stale banner and prep/grid.
    static let staleBannerToContentGap: CGFloat = 8
    static let filledCellBorderWidth: CGFloat = 1
    static let stickySeamCover: CGFloat = 1
}
