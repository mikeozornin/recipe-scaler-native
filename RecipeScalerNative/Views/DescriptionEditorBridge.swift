//
//  DescriptionEditorBridge.swift
//  RecipeScalerNative
//
//  Coordinates WKWebView Yjs editor ↔ yrs Y.Doc (006).
//

import Foundation

@MainActor
final class DescriptionEditorBridge: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading

    let recipeId: String
    private weak var syncService: YjsSyncService?
    private var webView: DescriptionEditorWebView.Coordinator?

    init(recipeId: String, syncService: YjsSyncService) {
        self.recipeId = recipeId
        self.syncService = syncService
        syncService.registerDescriptionEditor(self)
    }

    func attach(webView: DescriptionEditorWebView.Coordinator) {
        self.webView = webView
    }

    func detach(webView: DescriptionEditorWebView.Coordinator) {
        if self.webView === webView {
            self.webView = nil
        }
    }

    func beginSession() async {
        phase = .loading
        guard let syncService else {
            phase = .error(String(localized: "edit.error.documentNotLoaded"))
            return
        }
        do {
            let payload = try await syncService.descriptionEditorBootstrap(recipeId: recipeId)
            webView?.sendInit(state: payload.state)
            #if DEBUG
            AgentSyncDebugLog.write(
                hypothesisId: "006",
                location: "DescriptionEditorBridge.swift:beginSession",
                message: "description_editor_init",
                data: [
                    "recipeId": recipeId,
                    "stateBytes": String(payload.state.count),
                ]
            )
            #endif
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func handleWebMessage(_ body: Any) {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "loaded":
            Task { await beginSession() }
        case "ready":
            phase = .ready
            #if DEBUG
            AgentSyncDebugLog.write(
                hypothesisId: "006",
                location: "DescriptionEditorBridge.swift:ready",
                message: "description_editor_ready",
                data: ["recipeId": recipeId]
            )
            #endif
        case "update":
            guard let numbers = dict["update"] as? [NSNumber], !numbers.isEmpty else { return }
            let data = Data(numbers.map { UInt8(truncating: $0) })
            Task {
                try? await syncService?.applyDescriptionEditorUpdate(recipeId: recipeId, update: data)
            }
        default:
            break
        }
    }

    func applyRemoteUpdate(_ update: Data) {
        webView?.sendApplyUpdate(update)
    }

    func flushPendingSync() async {
        await syncService?.flushPendingEdits()
    }

    func reportLoadFailure(_ message: String) {
        phase = .error(message)
    }

    func teardown() {
        syncService?.unregisterDescriptionEditor(recipeId: recipeId)
    }
}