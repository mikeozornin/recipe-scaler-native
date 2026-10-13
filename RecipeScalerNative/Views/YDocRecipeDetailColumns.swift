import SwiftUI

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
                    // Steps text ≤ 660 with 32 pt sides (the sections bring 16 of them).
                    .frame(
                        maxWidth: IPadLayoutMetrics.stepsMaxWidth + 2 * Self.sectionInset,
                        alignment: .leading
                    )
                    .padding(.horizontal, IPadLayoutMetrics.stepsHorizontalPadding - Self.sectionInset)
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
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) {
        self.init(detailWidth: detailWidth, left: left, right: right, rightBar: { EmptyView() })
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
