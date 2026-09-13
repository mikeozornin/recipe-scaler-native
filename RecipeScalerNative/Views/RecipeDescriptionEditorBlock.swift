//
//  RecipeDescriptionEditorBlock.swift
//  RecipeScalerNative
//
//  Inline WKWebView description editor in recipe detail scroll (019).
//

import SwiftUI

struct RecipeDescriptionEditorBlock: View {
    let recipeId: String
    let accentColor: Color
    let syncService: YjsSyncService
    let scaleFactor: Double
    let ingredients: [IngredientData]
    @Bindable var chrome: DescriptionEditorChromeState
    var onNodeClick: ((DescriptionNodeClick) -> Void)?
    var processTableRecipe: RecipeData? = nil

    @Environment(\.locale) private var locale
    @Environment(\.apiClient) private var apiClient
    @State private var bridge: DescriptionEditorBridge
    @State private var processTableRebuild: ProcessTableRebuildModel?

    init(
        recipeId: String,
        accentColor: Color,
        syncService: YjsSyncService,
        scaleFactor: Double,
        ingredients: [IngredientData],
        chrome: DescriptionEditorChromeState,
        onNodeClick: ((DescriptionNodeClick) -> Void)? = nil,
        processTableRecipe: RecipeData? = nil
    ) {
        self.recipeId = recipeId
        self.accentColor = accentColor
        self.syncService = syncService
        self.scaleFactor = scaleFactor
        self.ingredients = ingredients
        self.chrome = chrome
        self.onNodeClick = onNodeClick
        self.processTableRecipe = processTableRecipe
        _bridge = State(
            initialValue: DescriptionEditorBridge(
                recipeId: recipeId,
                syncService: syncService,
                presentation: .inline
            )
        )
    }

    /// Full content height — parent ScrollView scrolls; WebView never scrolls inline.
    private var resolvedHeight: CGFloat {
        switch bridge.phase {
        case .loading, .error:
            return DescriptionEditorLayoutMetrics.minEmbeddedHeight
        case .ready:
            return max(DescriptionEditorLayoutMetrics.minInlineContentHeight, bridge.contentHeight)
        }
    }

    private var bannerKind: ProcessTableStatusBanner.Kind? {
        guard let recipe = processTableRecipe else { return nil }
        if recipe.processTable == nil { return .missing }
        if recipe.isProcessTableStale { return .outdated }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("description.instructions")
                .font(AppTypography.title2)
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)

            if let bannerKind {
                ProcessTableStatusBanner(
                    kind: bannerKind,
                    canRecalculate: syncService.connectionState.isConnected,
                    isOnline: syncService.connectionState.isConnected,
                    isRebuilding: processTableRebuild?.isRebuilding == true,
                    onRecalculate: {
                        let model = processTableRebuild
                        model?.rebuild(
                            recipeId: recipeId,
                            userId: syncService.currentUserId,
                            syncService: syncService
                        )
                    }
                )
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
            }

            ZStack(alignment: .top) {
                DescriptionEditorWebView(
                    bridge: bridge,
                    allowsScrolling: false,
                    accentColor: accentColor,
                    onKeyboardDone: { chrome.blurEditor() }
                )
                    .frame(height: resolvedHeight)
                    .opacity(bridge.phase == .ready ? 1 : 0.35)

                if bridge.phase == .loading {
                    ProgressView("description.editor.loading")
                        .frame(maxWidth: .infinity, minHeight: resolvedHeight)
                }

                if case .error(let message) = bridge.phase {
                    Text(message)
                        .appBody()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: resolvedHeight)
                        .padding()
                }
            }
            .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
        }
        .accessibilityIdentifier("recipe_description_editor_inline")
        .task {
            if processTableRebuild == nil {
                processTableRebuild = ProcessTableRebuildModel(api: apiClient)
            }
            await syncService.suspendRecipeRefresh()
        }
        .onAppear {
            chrome.bind(bridge: bridge)
            pushScaleToEditor()
        }
        .onDisappear {
            processTableRebuild?.cancel()
            Task { @MainActor in
                await syncService.flushPendingEdits()
                bridge.teardown()
                chrome.reset()
                await syncService.resumeRecipeRefresh()
            }
        }
        .onChange(of: bridge.phase) { _, phase in
            if phase == .ready { pushScaleToEditor() }
        }
        .onChange(of: scaleFactor) { _, _ in pushScaleToEditor() }
        .onChange(of: ingredients.count) { _, _ in pushScaleToEditor() }
        .onChange(of: locale) { _, _ in pushScaleToEditor() }
        .onChange(of: bridge.nodeClickSequence) { _, _ in
            guard let click = bridge.lastNodeClick else { return }
            onNodeClick?(click)
        }
    }

    private func pushScaleToEditor() {
        bridge.updateScale(
            scaleFactor: scaleFactor,
            ingredients: ingredients,
            locale: locale.identifier
        )
    }
}
