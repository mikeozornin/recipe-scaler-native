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
/// The divider drags the left column within 320–480 pt while the steps keep 320 pt
/// (`IPadLayoutPolicy.detailLeftWidth`). The width is saved when the divider is released
/// and only read during layout, so a narrower window, the list column or the inspector
/// squeeze the column without losing the saved value.
struct YDocRecipeDetailColumns<Left: View, Right: View>: View {
    let detailWidth: CGFloat
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    @AppStorage(IPadLayoutMetrics.detailLeftColumnWidthStorageKey)
    private var savedLeftWidth: Double?
    /// Live width while the divider is dragged.
    @State private var dragWidth: CGFloat?
    @State private var dragStartWidth: CGFloat?
    @State private var isHoveringDivider = false

    /// Phone sections carry their own 16 pt side insets (`.padding(.horizontal)`).
    private static var sectionInset: CGFloat { 16 }

    private var layoutLeftWidth: CGFloat {
        clamped(savedLeftWidth.map { CGFloat($0) })
    }

    private var leftWidth: CGFloat {
        dragWidth ?? layoutLeftWidth
    }

    private func clamped(_ preferred: CGFloat?) -> CGFloat {
        IPadLayoutPolicy.detailLeftWidth(preferred: preferred, detailWidth: detailWidth)
            ?? IPadLayoutMetrics.detailLeftWidth
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
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeDetailRightColumn)
        }
        .overlay(alignment: .leading) {
            divider
        }
    }

    // MARK: - Divider

    private var divider: some View {
        let isActive = dragWidth != nil || isHoveringDivider
        return Capsule()
            .fill(isActive ? Color(.tertiaryLabel) : Color(.tertiarySystemFill))
            .frame(width: RecipeColumnDividerMetrics.gripWidth, height: RecipeColumnDividerMetrics.gripHeight)
            .frame(width: IPadLayoutMetrics.columnDividerHitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHoveringDivider = $0 }
            .gesture(dragGesture)
            .accessibilityElement()
            .accessibilityLabel(Text("ipad.recipe.columnDivider"))
            .accessibilityValue(Text(verbatim: "\(Int(leftWidth.rounded())) pt"))
            .accessibilityAdjustableAction { direction in
                let step = IPadLayoutMetrics.columnDividerAccessibilityStep
                switch direction {
                case .increment:
                    savedLeftWidth = Double(clamped(leftWidth + step))
                case .decrement:
                    savedLeftWidth = Double(clamped(leftWidth - step))
                @unknown default:
                    break
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeColumnDivider)
            // Centered on the 1 pt line.
            .padding(
                .leading,
                leftWidth + IPadLayoutMetrics.columnDividerWidth / 2 - IPadLayoutMetrics.columnDividerHitWidth / 2
            )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStartWidth ?? leftWidth
                dragStartWidth = start
                dragWidth = clamped(start + value.translation.width)
            }
            .onEnded { _ in
                // Written only on release; layout never writes it back.
                if let dragWidth {
                    savedLeftWidth = Double(dragWidth)
                }
                dragWidth = nil
                dragStartWidth = nil
            }
    }
}

/// The grip on the recipe column divider (prototype `.dt-split::after`).
private enum RecipeColumnDividerMetrics {
    static let gripWidth: CGFloat = 7
    static let gripHeight: CGFloat = 44
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
