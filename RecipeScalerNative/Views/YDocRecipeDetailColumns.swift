import SwiftUI
import UIKit

/// Spec 081 — the recipe shown in the panel of the iPad split (`IPadRecipesSplitView`).
/// `nil` on the phone and in a compact iPad window: the recipe keeps its phone layout.
struct RecipeDetailPadPanel {
    /// Width of the recipe panel (`IPadLayout.detailWidth`).
    let detailWidth: CGFloat
    let toolbarStyle: IPadDetailToolbarStyle
    /// ✦ in the toolbar opens the assistant (`IPadAssistantToolbarButton`); `nil` while the
    /// top tab bar shows the pinned «Ассистент» tab (`IPadLayoutPolicy.showsAssistantToolbarButton`).
    let assistantCoordinator: AppShellCoordinator?
}

/// The recipe in two columns (T025, FR-012, FR-012a, plan.md Р6): photo, title, servings,
/// ingredients and nutrition on the left, the steps on the right; the columns scroll
/// independently.
///
/// The left column has a fixed width, 400 pt, cut to keep the steps at 320 pt
/// (`IPadLayoutPolicy.detailLeftWidth`, 399 at the 720 pt threshold), with a static
/// 1 pt hairline between the columns. No draggable divider (owner decision 2026-10-13).
///
/// In edit (US5, T042) the left column holds the edit header and the ingredients, the
/// right one the steps editor with its formatting bar (`rightBar`) pinned to the bottom of
/// that column above the keyboard, and `rightBottomPadding` keeps the last line clear of it.
struct YDocRecipeDetailColumns<Left: View, Right: View, RightBar: View>: View {
    let detailWidth: CGFloat
    /// Hands-free scrolling (FR-026, T036) moves the steps: the probe sits here, at the top
    /// of the steps column, so its scroll view is the one the probe finds.
    let scrollProbe: DetailScrollViewProbeBox
    var rightBottomPadding: CGFloat = 0
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right
    @ViewBuilder let rightBar: () -> RightBar

    /// Phone sections carry their own 16 pt side insets (`.padding(.horizontal)`).
    private static var sectionInset: CGFloat { 16 }

    private var leftWidth: CGFloat {
        IPadLayoutPolicy.detailLeftWidth(detailWidth: detailWidth) ?? IPadLayoutMetrics.detailLeftWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                left()
                    .padding(.bottom, RecipeDetailLayoutMetrics.descriptionBottomPadding)
            }
            .frame(width: leftWidth)
            .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeDetailLeftColumn)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: IPadLayoutMetrics.columnDividerWidth)
                .ignoresSafeArea(edges: .bottom)

            ScrollView {
                right()
                    // Behind the steps, so the probe adds no height above «Инструкции».
                    .background(alignment: .topLeading) {
                        DetailScrollViewProbe(box: scrollProbe)
                            .frame(width: 1, height: 1)
                            .accessibilityHidden(true)
                    }
                    // Steps text ≤ 660 with the sections' own 16 pt sides, as on the left.
                    .frame(
                        maxWidth: IPadLayoutMetrics.stepsMaxWidth + 2 * Self.sectionInset,
                        alignment: .leading
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, rightBottomPadding)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeDetailRightColumn)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                rightBar()
            }
        }
    }
}

extension YDocRecipeDetailColumns where RightBar == EmptyView {
    /// Reading: no bar under the steps.
    init(
        detailWidth: CGFloat,
        scrollProbe: DetailScrollViewProbeBox,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) {
        self.init(
            detailWidth: detailWidth,
            scrollProbe: scrollProbe,
            left: left,
            right: right,
            rightBar: { EmptyView() }
        )
    }
}

/// Spec 081 — the top of the steps column: the cap top of «Инструкции» lines up with what
/// the left column starts with, the top edge of the photo (or of its placeholder in edit, or
/// of the legacy banner) or the cap top of the recipe title (owner decision 2026-10-13).
enum RecipeStepsColumnMetrics {
    /// `headerRowHeight`: reading centres the header in a 44 pt row (`StepsSection`); the
    /// editor's header (`RecipeDescriptionEditorBlock`) has no row, `nil`.
    static func topPadding(leftStartsWithBox: Bool, headerRowHeight: CGFloat?) -> CGFloat {
        let title = AppTypography.uiFont(AppFonts.display, size: AppTypography.recipeTitleSize, fallbackFamily: AppFonts.display)
        let header = AppTypography.uiFont(AppFonts.display, size: AppTypography.title2Size, fallbackFamily: AppFonts.display)
        // The photo and the title both start at the left column's 16 pt top padding.
        let leftTop = RecipeDetailLayoutMetrics.titleTopSpacing + (leftStartsWithBox ? 0 : capInset(title))
        let rowInset = headerRowHeight.map { max(0, ($0 - header.lineHeight) / 2) } ?? 0
        return leftTop - rowInset - capInset(header)
    }

    /// From the top of a line of text to the top of its capitals.
    private static func capInset(_ font: UIFont) -> CGFloat {
        font.ascender - font.capHeight
    }
}

/// One-column recipe on `.padRegular`: the phone column, ≤ 720 pt and centered (FR-012).
struct RecipeDetailSingleColumnWidth: ViewModifier {
    let isPadPanel: Bool

    func body(content: Content) -> some View {
        if isPadPanel {
            content
                .frame(maxWidth: IPadLayoutMetrics.singleColumnMaxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}
