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
    @State private var bridge: DescriptionEditorBridge?
    @State private var exportSessionActive = false

    var body: some View {
        Group {
            if exportSessionActive, let bridge {
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
            syncExportSessionActive(with: syncService.descriptionWireExportRecipeIds)
        }
        .onChange(of: syncService.descriptionWireExportRecipeIds) { _, ids in
            syncExportSessionActive(with: ids)
        }
        .onChange(of: exportSessionActive && (bridge?.phase == .ready)) { _, ready in
            guard ready else { return }
            Task { await runExport() }
        }
    }

    private func syncExportSessionActive(with ids: Set<String>) {
        let should = ids.contains(recipeId)
        guard should != exportSessionActive else { return }
        if should {
            if bridge == nil {
                bridge = DescriptionEditorBridge(
                    recipeId: recipeId,
                    syncService: syncService,
                    presentation: .inline
                )
            }
            exportSessionActive = true
        } else {
            exportSessionActive = false
            bridge?.teardown()
            bridge = nil
        }
    }

    private func runExport() async {
        guard let bridge else { return }
        await bridge.flushEditorEdits()
        syncService.finishDescriptionWireExport(recipeId: recipeId)
        exportSessionActive = false
        bridge.teardown()
        self.bridge = nil
    }
}
