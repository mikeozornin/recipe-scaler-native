//
//  DescriptionWireExportHost.swift
//  RecipeScalerNative
//
//  Headless one-shot WebView export when read-mode reconnect cannot push yjs wire bytes.
//

import SwiftUI

struct DescriptionWireExportHost: View {
    let recipeId: String
    @Bindable var syncService: YjsSyncService
    @State private var bridge: DescriptionEditorBridge
    @State private var exportSessionActive = false

    init(recipeId: String, syncService: YjsSyncService) {
        self.recipeId = recipeId
        self.syncService = syncService
        _bridge = State(
            initialValue: DescriptionEditorBridge(
                recipeId: recipeId,
                syncService: syncService,
                presentation: .inline
            )
        )
    }

    var body: some View {
        Group {
            if exportSessionActive {
                DescriptionEditorWebView(
                    bridge: bridge,
                    allowsScrolling: false
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            exportSessionActive = syncService.descriptionWireExportRecipeIds.contains(recipeId)
        }
        .onChange(of: syncService.descriptionWireExportRecipeIds) { _, ids in
            let should = ids.contains(recipeId)
            guard should != exportSessionActive else { return }
            exportSessionActive = should
            if !should {
                bridge.teardown()
            }
        }
        .onChange(of: bridge.phase) { _, phase in
            guard exportSessionActive, phase == .ready else { return }
            Task { await runExport() }
        }
    }

    private func runExport() async {
        await bridge.flushEditorEdits()
        syncService.finishDescriptionWireExport(recipeId: recipeId)
        exportSessionActive = false
    }
}
