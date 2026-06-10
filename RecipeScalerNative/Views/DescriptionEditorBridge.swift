//
//  DescriptionEditorBridge.swift
//  RecipeScalerNative
//
//  Coordinates WKWebView Yjs editor ↔ yrs Y.Doc (006, 019 v2).
//

import Foundation
import SwiftUI

enum DescriptionEditorPresentation {
    case inline
    case fullscreen
}

struct DescriptionEditorSelectionState: Equatable {
    var bold = false
    var heading1 = false
    var highlight = false
    var bulletList = false
    var orderedList = false
    var hasSelection = false
    var selectedText = ""
    var canBold = true
    var canHeading1 = true
    var canHighlight = true
    var canBulletList = true
    var canOrderedList = true

    var canMarkTimer: Bool { hasSelection && !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canMarkIngredient: Bool { canMarkTimer }
}

enum DescriptionEditorHeightMode: Equatable {
    case embedded
    case focus
}

enum DescriptionEditorLayoutMetrics {
    static let minEmbeddedHeight: CGFloat = 280
    static let embeddedMaxHeight: CGFloat = 2000
    static let focusMinHeight: CGFloat = 320
}

@MainActor
final class DescriptionEditorBridge: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isFocused = false
    @Published private(set) var contentHeight: CGFloat = DescriptionEditorLayoutMetrics.minEmbeddedHeight
    @Published private(set) var selectionState = DescriptionEditorSelectionState()

    let recipeId: String
    let presentation: DescriptionEditorPresentation
    private weak var syncService: YjsSyncService?
    private var webView: DescriptionEditorWebView.Coordinator?

    var heightMode: DescriptionEditorHeightMode {
        contentHeight > DescriptionEditorLayoutMetrics.embeddedMaxHeight ? .focus : .embedded
    }

    init(
        recipeId: String,
        syncService: YjsSyncService,
        presentation: DescriptionEditorPresentation = .inline
    ) {
        self.recipeId = recipeId
        self.presentation = presentation
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
            webView?.sendConfigure(presentation: presentation)
            webView?.sendInit(state: payload.state)
            #if DEBUG
            AgentSyncDebugLog.write(
                hypothesisId: "019",
                location: "DescriptionEditorBridge.swift:beginSession",
                message: "description_editor_init",
                data: [
                    "recipeId": recipeId,
                    "stateBytes": String(payload.state.count),
                    "presentation": presentation == .inline ? "inline" : "fullscreen",
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
                hypothesisId: "019",
                location: "DescriptionEditorBridge.swift:ready",
                message: "description_editor_ready",
                data: ["recipeId": recipeId]
            )
            #endif
        case "update":
            guard let numbers = dict["update"] as? [NSNumber], !numbers.isEmpty else { return }
            let data = Data(numbers.map { UInt8(truncating: $0) })
            // #region agent log
            DebugSessionNDJSONLog.write(
                hypothesisId: "H1",
                location: "DescriptionEditorBridge.swift:update",
                message: "swift_received_js_update",
                data: [
                    "recipeId": recipeId,
                    "bytes": String(data.count),
                ]
            )
            // #endregion
            Task {
                try? await syncService?.applyDescriptionEditorUpdate(recipeId: recipeId, update: data)
            }
        case "focus":
            isFocused = true
        case "blur":
            isFocused = false
        case "contentHeight":
            if let height = dict["height"] as? Double, height > 0 {
                contentHeight = CGFloat(height)
            } else if let height = dict["height"] as? NSNumber {
                contentHeight = CGFloat(truncating: height)
            }
        case "selectionState":
            selectionState = Self.parseSelectionState(dict)
        default:
            break
        }
    }

    func sendCommand(name: String, args: [String: Any]? = nil) {
        webView?.sendCommand(name: name, args: args)
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

    private static func parseSelectionState(_ dict: [String: Any]) -> DescriptionEditorSelectionState {
        func bool(_ key: String) -> Bool {
            (dict[key] as? Bool) == true || (dict[key] as? NSNumber)?.boolValue == true
        }
        func string(_ key: String) -> String {
            dict[key] as? String ?? ""
        }
        return DescriptionEditorSelectionState(
            bold: bool("bold"),
            heading1: bool("heading1"),
            highlight: bool("highlight"),
            bulletList: bool("bulletList"),
            orderedList: bool("orderedList"),
            hasSelection: bool("hasSelection"),
            selectedText: string("selectedText"),
            canBold: dict["canBold"] == nil ? true : bool("canBold"),
            canHeading1: dict["canHeading1"] == nil ? true : bool("canHeading1"),
            canHighlight: dict["canHighlight"] == nil ? true : bool("canHighlight"),
            canBulletList: dict["canBulletList"] == nil ? true : bool("canBulletList"),
            canOrderedList: dict["canOrderedList"] == nil ? true : bool("canOrderedList")
        )
    }
}
