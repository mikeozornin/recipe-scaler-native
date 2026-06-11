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
    @ObservedObject var chrome: DescriptionEditorChromeState
    var onNodeClick: ((DescriptionNodeClick) -> Void)?

    @StateObject private var bridge: DescriptionEditorBridge

    init(
        recipeId: String,
        accentColor: Color,
        syncService: YjsSyncService,
        chrome: DescriptionEditorChromeState,
        onNodeClick: ((DescriptionNodeClick) -> Void)? = nil
    ) {
        self.recipeId = recipeId
        self.accentColor = accentColor
        self.syncService = syncService
        self.chrome = chrome
        self.onNodeClick = onNodeClick
        _bridge = StateObject(
            wrappedValue: DescriptionEditorBridge(
                recipeId: recipeId,
                syncService: syncService,
                presentation: .inline
            )
        )
    }

    /// Full content height — parent ScrollView scrolls; WebView never scrolls inline.
    private var resolvedHeight: CGFloat {
        max(DescriptionEditorLayoutMetrics.minEmbeddedHeight, bridge.contentHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions")
                .font(AppTypography.title2)
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)

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
        .onAppear {
            chrome.bind(bridge: bridge)
        }
        .onDisappear {
            bridge.teardown()
            chrome.reset()
        }
        .onChange(of: bridge.nodeClickSequence) { _, _ in
            guard let click = bridge.lastNodeClick else { return }
            onNodeClick?(click)
        }
    }
}
