import SwiftUI
import UIKit

struct ProcessTableCookingView: View {
    let recipe: RecipeData
    let scaleFactor: Double
    var allowsRebuild: Bool
    var restoreAwakeOnDismiss: Bool
    /// Running-timers panel source. Optional so previews/tests can skip the heavy manager.
    var timerManager: TimerManager? = nil
    var syncService: YjsSyncService? = nil
    /// Retained for the overlay lifetime. Must not be `@State` on the recipe
    /// card: cooking replaces that view, and a captured optional becomes a no-op.
    @Bindable var rebuildModel: ProcessTableRebuildModel
    var onStartTimer: (ProcessTableTimerChip) -> Void

    @State private var session = ProcessTableCookingSession()
    @State private var orientationGate = ProcessTableCookingOrientationGate()
    @State private var containerSize = CGSize(width: 420, height: 868)
    @State private var trailingSafeArea: CGFloat = 0
    @State private var isTimerPanelCollapsed = true

    private var displayedRecipe: RecipeData {
        if let live = syncService?.currentRecipe, live.id == recipe.id, live.processTable != nil {
            return live
        }
        return recipe
    }

    private var table: ProcessTableV1? { displayedRecipe.processTable }

    private var isOnline: Bool {
        syncService?.connectionState.isConnected == true
    }

    private var canRecalculate: Bool {
        allowsRebuild && isOnline
    }

    var body: some View {
        Group {
            if let table {
                cookingBody(table: table)
            } else {
                Color.clear
                    .onAppear { ProcessTableCookingPresenter.dismissOverlay() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(.systemBackground)
                .ignoresSafeArea(edges: .horizontal)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    noteContainerSize(size)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.safeAreaInsets.trailing
                } action: { inset in
                    trailingSafeArea = max(0, inset)
                }
        }
        .background {
            ProcessTableInterfaceOrientationObserver { orientation in
                applyInterfaceOrientation(orientation)
            }
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(.top, ProcessTableLayout.cookingCloseTopPad)
                .padding(.trailing, ProcessTableLayout.cookingCloseTrailingPad)
                .safeAreaPadding(.top)
                .ignoresSafeArea(edges: .trailing)
        }
        .onAppear {
            ProcessTableCookingPresenter.beginLandscapeSession()
            ScreenAwakeController.setActive(true)
        }
        .onDisappear {
            ScreenAwakeController.setActive(restoreAwakeOnDismiss)
        }
    }

    private func noteContainerSize(_ size: CGSize) {
        guard let orientation = ProcessTableCookingOrientationGate.interfaceOrientation(from: size) else {
            return
        }
        containerSize = size
        applyInterfaceOrientation(orientation)
    }

    private func applyInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        if orientationGate.apply(orientation) == .reassertLandscape {
            ProcessTableCookingPresenter.reassertLandscape()
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        let action = {
            ProcessTableCookingPresenter.dismissOverlay()
        }
        // Toolbar `.glass` outside a nav bar renders as an opaque white pill
        // (no Liquid Glass). Match recipe-detail icon chrome: plain + glassEffect.
        if #available(iOS 26.0, *) {
            Button(action: action) {
                AppToolbarStyle.icon("xmark")
                    .frame(width: ProcessTableLayout.ctaMinHit, height: ProcessTableLayout.ctaMinHit)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("common.close")
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeProcessTableClose)
        } else {
            Button(action: action) {
                AppToolbarStyle.icon("xmark")
                    .frame(width: ProcessTableLayout.ctaMinHit, height: ProcessTableLayout.ctaMinHit)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .accessibilityLabel("common.close")
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeProcessTableClose)
        }
    }

    @ViewBuilder
    private func cookingBody(table: ProcessTableV1) -> some View {
        let timerMap = ProcessTableTimers.map(
            descriptionHtml: displayedRecipe.description ?? "",
            columns: table.columns
        )
        let visibleWidth = max(
            0,
            containerSize.width
                - ProcessTableLayout.cookingLeadingEdgePad
                - ProcessTableLayout.cookingTrailingEdgePad
                + trailingSafeArea
        )
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: displayedRecipe.name)
                    .font(AppTypography.title2)
                    .lineLimit(1)
                    .padding(.trailing, ProcessTableLayout.ctaMinHit + ProcessTableLayout.matrixPadding)
                    .padding(.bottom, ProcessTableLayout.prepVerticalPad)
                    .accessibilityAddTraits(.isHeader)

                if displayedRecipe.isProcessTableStale {
                    ProcessTableStatusBanner(
                        kind: .outdated,
                        canRecalculate: canRecalculate,
                        isOnline: isOnline,
                        isRebuilding: rebuildModel.isRebuilding,
                        onRecalculate: {
                            rebuildModel.rebuild(
                                recipeId: displayedRecipe.id,
                                userId: syncService?.currentUserId,
                                syncService: syncService
                            )
                        }
                    )
                    .padding(.bottom, ProcessTableLayout.staleBannerToContentGap)
                }

                ProcessTablePrepStack(columns: table.prepColumns)
                    .padding(.bottom, ProcessTableLayout.prepStackToGridGap)

                ProcessTableGrid(
                    table: table,
                    ingredients: displayedRecipe.ingredients,
                    scaleFactor: scaleFactor,
                    session: session,
                    visibleWidth: visibleWidth,
                    timerMap: timerMap,
                    onStartTimer: onStartTimer
                )
                .frame(width: visibleWidth)
                .ignoresSafeArea(edges: .trailing)
                // Live-scene XCTest walks scroll content, not the Close overlay
                // (glassEffect). Keep a real UIView identifier next to the grid.
                .background {
                    ProcessTableAccessibilityIdentifierProbe(id: AccessibilityIdentifiers.recipeProcessTableClose)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                }
            }
            .padding(.leading, ProcessTableLayout.cookingLeadingEdgePad)
            .padding(.trailing, ProcessTableLayout.cookingTrailingEdgePad)
            .padding(.top, ProcessTableLayout.cookingContentTopPad)
            .safeAreaPadding(.top)
            .padding(.bottom, ProcessTableLayout.matrixPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !timerMap.leftover.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: ProcessTableLayout.timerChipGap) {
                            ForEach(timerMap.leftover) { chip in
                                ProcessTableTimerChipButton(chip: chip, onStart: onStartTimer)
                            }
                        }
                        .padding(ProcessTableLayout.leftoverBarPadding)
                    }
                    .background(.bar)
                }
                // Same running-timers panel as the recipe card (web parity: the
                // panel stays visible in cooking mode).
                if let timerManager {
                    MobileTimerPanel(isCollapsed: $isTimerPanelCollapsed, presentation: .legacy)
                        .environment(timerManager)
                }
            }
        }
    }
}

#Preview {
    let hash = ProcessTableSourceHash.compute(
        ingredients: [
            .init(id: "a", originalAmount: 200, unit: "g"),
            .init(id: "b", originalAmount: 1, unit: "pcs"),
        ],
        steps: ["Mix dry", "Bake"]
    )
    let recipe = RecipeData(
        id: "preview",
        name: "Preview loaf",
        servings: 1,
        color: "#3b82f6",
        version: "v3",
        description: "<ol><li>Mix dry</li><li>Bake</li></ol>",
        ingredients: [
            IngredientData(id: "a", name: "Flour", originalAmount: "200", unit: "g"),
            IngredientData(id: "b", name: "Water", originalAmount: "120", unit: "g"),
        ],
        nutrition: nil,
        isPublic: false,
        hasSteps: true,
        createdAt: "",
        updatedAt: "",
        imageUrl: nil,
        imageAspectRatio: nil,
        originalRecipeLink: nil,
        originalRecipe: nil,
        processTableRaw: """
        {"version":1,"sourceHash":"\(hash)","columns":[{"id":"c1","title":"Mix","kind":"cook","stepIndex":0},{"id":"c2","title":"Bake","kind":"cook","stepIndex":1}],"assignments":[{"ingredientId":"a","columnId":"c1"},{"ingredientId":"b","columnId":"c2"}]}
        """
    )
    return ProcessTableCookingView(
        recipe: recipe,
        scaleFactor: 1,
        allowsRebuild: false,
        restoreAwakeOnDismiss: false,
            rebuildModel: ProcessTableRebuildModel.makePreview(),
        onStartTimer: { _ in }
    )
}

