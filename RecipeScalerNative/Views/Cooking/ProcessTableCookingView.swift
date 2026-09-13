import SwiftUI
import UIKit

struct ProcessTableCookingView: View {
    let recipe: RecipeData
    let scaleFactor: Double
    var allowsRebuild: Bool
    var restoreAwakeOnDismiss: Bool
    @Bindable var session: ProcessTableCookingSession
    @Bindable var rebuildModel: ProcessTableRebuildModel

    @Environment(\.appContainer) private var container
    @Environment(\.timerManager) private var timerManager

    @State private var orientationGate = ProcessTableCookingOrientationGate()
    @State private var containerSize = CGSize(width: 420, height: 868)
    @State private var trailingSafeArea: CGFloat = 0
    @State private var isTimerPanelCollapsed = true

    private var cooking: ProcessTableCookingCoordinator? { container?.cooking }
    private var syncService: YjsSyncService? { container?.sync }

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
                    .onAppear { closeCooking() }
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
            cooking?.beginLandscapeSession()
            ScreenAwakeController.setActive(true)
        }
        .onDisappear {
            rebuildModel.cancel()
            ScreenAwakeController.setActive(restoreAwakeOnDismiss)
        }
    }

    private func closeCooking() {
        rebuildModel.cancel()
        cooking?.dismiss()
    }

    private func noteContainerSize(_ size: CGSize) {
        let idiom = UIDevice.current.userInterfaceIdiom
        if let accepted = ProcessTableCookingOrientationGate.acceptedLayoutSize(size, idiom: idiom) {
            containerSize = accepted
        }
        guard let orientation = ProcessTableCookingOrientationGate.interfaceOrientation(from: size) else {
            return
        }
        applyInterfaceOrientation(orientation)
    }

    private func applyInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        if orientationGate.apply(orientation) == .reassertLandscape {
            cooking?.reassertLandscape()
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        let action = {
            closeCooking()
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
                    onStartTimer: startTimer
                )
                .frame(width: visibleWidth)
                .ignoresSafeArea(edges: .trailing)
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
                                ProcessTableTimerChipButton(chip: chip, onStart: startTimer)
                            }
                        }
                        .padding(ProcessTableLayout.leftoverBarPadding)
                    }
                    .background(.bar)
                }
                if let timerManager {
                    MobileTimerPanel(isCollapsed: $isTimerPanelCollapsed, presentation: .legacy)
                        .environment(timerManager)
                }
            }
        }
    }

    private func startTimer(_ chip: ProcessTableTimerChip) {
        guard let timerManager else { return }
        _ = timerManager.createAndStartTimer(
            name: chip.name,
            duration: TimeInterval(chip.duration),
            type: chip.type,
            recipeId: displayedRecipe.id
        )
    }
}

@MainActor
private func processTableCookingPreview() -> ProcessTableCookingView {
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
        session: ProcessTableCookingSession(),
        rebuildModel: ProcessTableRebuildModel.makePreview()
    )
}

#Preview {
    processTableCookingPreview()
}
