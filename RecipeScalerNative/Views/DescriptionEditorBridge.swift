//
//  DescriptionEditorBridge.swift
//  RecipeScalerNative
//
//  Coordinates WKWebView Yjs editor ↔ yrs Y.Doc (006, 019 v2).
//

import Foundation
import SwiftUI

final class DescriptionEditorDeinitCleaner: @unchecked Sendable {
    private let recipeId: String
    private weak var syncService: YjsSyncService?
    weak var bridge: DescriptionEditorBridge?

    init(recipeId: String, syncService: YjsSyncService) {
        self.recipeId = recipeId
        self.syncService = syncService
    }

    func clean() {
        let service = self.syncService
        let recipeId = self.recipeId
        let bridge = self.bridge
        Task { @MainActor in
            guard let bridge else { return }
            service?.unregisterDescriptionEditor(recipeId: recipeId, bridge: bridge)
        }
    }
}

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
    /// Placeholder while the editor bundle loads.
    static let minEmbeddedHeight: CGFloat = 280
    /// Inline frame floor once content is measured (tap target for empty editor).
    static let minInlineContentHeight: CGFloat = 36
    static let embeddedMaxHeight: CGFloat = 2000
    static let focusMinHeight: CGFloat = 320
}

/// Click on a timer or ingredient node in the description editor.
struct DescriptionNodeClick: Equatable {
    enum NodeType: String { case timer, ingredient }
    let nodeType: NodeType
    let timerId: String
    let duration: String
    let timerType: String
    let value: String
    let name: String
    let ingredientId: String
    let originalAmount: String
    let ratio: String
    let text: String
    let anchorX: CGFloat
    let anchorY: CGFloat
    let anchorWidth: CGFloat
    let anchorHeight: CGFloat

    var anchorRect: CGRect {
        CGRect(x: anchorX, y: anchorY, width: anchorWidth, height: anchorHeight)
    }

    /// Stable fallback key when `timerId` is missing from legacy markup.
    var timerMatchKey: String {
        if !timerId.isEmpty { return timerId }
        return "\(duration)-\(timerType)-\(value)-\(text)"
    }
}

@MainActor
@Observable
final class DescriptionEditorBridge {
    enum Phase: Equatable {
        case loading
        case ready
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var isFocused = false
    private(set) var contentHeight: CGFloat = DescriptionEditorLayoutMetrics.minInlineContentHeight
    private(set) var selectionState = DescriptionEditorSelectionState()
    private(set) var lastNodeClick: DescriptionNodeClick?
    private(set) var nodeClickSequence: UInt = 0

    private var suppressIncomingFocus = false
    private var htmlContinuations: [CheckedContinuation<String, Never>] = []

    let recipeId: String
    let presentation: DescriptionEditorPresentation
    private weak var syncService: YjsSyncService?
    private weak var webView: DescriptionEditorWebView.Coordinator?
    /// Serializes WebView → yrs applies so flush can await the last keystroke.
    private var applyChain: Task<Void, Never>?
    private var outboundFlushContinuations: [CheckedContinuation<Void, Never>] = []
    /// True while WebView has pending Yjs bytes we expect `outboundFlushed` to ack.
    /// JS only emits `outboundFlushed` when it actually flushed something; without this
    /// flag an idle `flushEditorEdits()` (e.g. on Done with no description edits) waits
    /// the full 2 s timeout before giving up.
    private var hasPendingOutbound = false
    private let cleaner: DescriptionEditorDeinitCleaner
    private var didRegisterWithSyncService = false

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
        self.cleaner = DescriptionEditorDeinitCleaner(recipeId: recipeId, syncService: syncService)
        cleaner.bridge = self
    }

    deinit {
        cleaner.clean()
    }

    func attach(webView: DescriptionEditorWebView.Coordinator) {
        self.webView = webView
        registerWithSyncServiceIfNeeded()
    }

    /// Test-only: registers the bridge with its sync service without requiring
    /// a real WebView coordinator. Mirrors what `attach(webView:)` does for the
    /// YjsMemoryLeakTests that assert the session count immediately after init.
    func test_registerWithSyncService() {
        registerWithSyncServiceIfNeeded()
    }

    private func registerWithSyncServiceIfNeeded() {
        guard !didRegisterWithSyncService else { return }
        didRegisterWithSyncService = true
        syncService?.registerDescriptionEditor(self)
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
        } catch {
            phase = .error(UserFacingAPIError.message(for: error))
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
            if let simulateText = DebugLaunchOptions.simulateDescriptionEditorText {
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    webView?.sendSimulateText(simulateText)
                }
            }
            if let simulateCommand = DebugLaunchOptions.simulateDescriptionEditorCommand {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    webView?.sendCommand(name: simulateCommand, args: nil)
                }
            }
            #endif
        case "syncState":
            guard let numbers = dict["update"] as? [NSNumber], !numbers.isEmpty else { return }
            let data = Data(numbers.map { UInt8(truncating: $0) })
            enqueueDescriptionSyncState(data)
        case "update":
            guard let numbers = dict["update"] as? [NSNumber], !numbers.isEmpty else { return }
            let data = Data(numbers.map { UInt8(truncating: $0) })
            enqueueDescriptionUpdate(data)
        case "outboundFlushed":
            resumeOutboundFlushWaiters()
        case "focus":
            guard !suppressIncomingFocus else { return }
            isFocused = true
        case "blur":
            suppressIncomingFocus = false
            isFocused = false
        case "contentHeight":
            if let height = dict["height"] as? Double, height > 0 {
                contentHeight = CGFloat(height)
            } else if let height = dict["height"] as? NSNumber {
                contentHeight = CGFloat(truncating: height)
            }
        case "selectionState":
            selectionState = Self.parseSelectionState(dict)
        case "html":
            let html = (dict["html"] as? String) ?? ""
            resumeHtmlWaiters(with: html)
        case "nodeClick":
            lastNodeClick = Self.parseNodeClick(dict)
            nodeClickSequence &+= 1
        default:
            break
        }
    }

    func sendCommand(name: String, args: [String: Any]? = nil) {
        webView?.sendCommand(name: name, args: args)
    }

    /// Live ingredient scaling in the editor (Tiptap `scaleStorage` + ingredient NodeView).
    func updateScale(scaleFactor: Double, ingredients: [IngredientData], locale: String) {
        let payload: [[String: Any]] = ingredients.compactMap { ing in
            guard ing.hasQuantity else { return nil }
            var item: [String: Any] = ["id": ing.id]
            if let amount = Double(ing.originalAmount.replacingOccurrences(of: ",", with: ".")) {
                item["originalAmount"] = amount
            } else if !ing.originalAmount.isEmpty {
                item["originalAmount"] = ing.originalAmount
            }
            return item
        }
        webView?.sendSetScale(scaleFactor: scaleFactor, ingredients: payload, locale: locale)
    }

    /// Dismiss keyboard and clear focus (e.g. keyboard accessory Done).
    func dismissEditingFocus() {
        suppressIncomingFocus = true
        isFocused = false
        sendCommand(name: "blur")
        webView?.resignEditingKeyboard()
    }

    func applyRemoteUpdate(_ update: Data) {
        webView?.sendApplyUpdate(update)
    }

    /// Push debounced WebView Yjs bytes into yrs and wait until applied (Done / leave edit).
    func flushEditorEdits() async {
        guard phase == .ready else { return }
        // Fast path: nothing enqueued since the last ack — JS won't emit `outboundFlushed`,
        // so don't send `flush` and don't wait (otherwise we burn the full 2 s timeout).
        if hasPendingOutbound {
            sendCommand(name: "flush")
            await waitForOutboundFlushed()
        }
        await applyChain?.value
    }

    private func enqueueDescriptionUpdate(_ data: Data) {
        let service = syncService
        let id = recipeId
        let prior = applyChain
        hasPendingOutbound = true
        applyChain = Task { @MainActor in
            await prior?.value
            try? await service?.applyDescriptionEditorUpdate(recipeId: id, update: data)
        }
    }

    private func enqueueDescriptionSyncState(_ data: Data) {
        let service = syncService
        let id = recipeId
        let prior = applyChain
        applyChain = Task { @MainActor in
            await prior?.value
            await service?.applyDescriptionSyncState(recipeId: id, state: data)
        }
    }

    private func resumeOutboundFlushWaiters() {
        hasPendingOutbound = false
        let waiters = outboundFlushContinuations
        outboundFlushContinuations.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func waitForOutboundFlushed(timeout: Duration = .seconds(2)) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.outboundFlushContinuations.append(continuation)
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            _ = await group.next()
            group.cancelAll()
            resumeOutboundFlushWaiters()
        }
    }

    func flushPendingSync() async {
        await syncService?.flushPendingEdits()
    }

    func reportLoadFailure(_ message: String) {
        phase = .error(message)
    }

    /// Request current editor HTML (resolves after JS posts `html`).
    func requestHTML() async -> String {
        guard phase == .ready else { return "" }
        return await withTaskGroup(of: String.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                    self.htmlContinuations.append(continuation)
                    self.sendCommand(name: "getHTML")
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return ""
            }
            let result = await group.next() ?? ""
            group.cancelAll()
            self.resumeHtmlWaiters(with: result)
            return result
        }
    }

    private func resumeHtmlWaiters(with html: String) {
        let waiters = htmlContinuations
        htmlContinuations.removeAll()
        for waiter in waiters {
            waiter.resume(returning: html)
        }
    }

    func teardown() {
        syncService?.unregisterDescriptionEditor(recipeId: recipeId, bridge: self)
        resumeHtmlWaiters(with: "")
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

    private static func parseNodeClick(_ dict: [String: Any]) -> DescriptionNodeClick {
        func string(_ key: String) -> String {
            dict[key] as? String ?? ""
        }
        func cgFloat(_ key: String) -> CGFloat {
            if let value = dict[key] as? Double { return CGFloat(value) }
            if let value = dict[key] as? NSNumber { return CGFloat(truncating: value) }
            return 0
        }
        let rawType = string("nodeType")
        let nodeType = DescriptionNodeClick.NodeType(rawValue: rawType) ?? .timer
        let timerTypeRaw = string("timerType")
        return DescriptionNodeClick(
            nodeType: nodeType,
            timerId: string("timerId"),
            duration: string("duration"),
            timerType: timerTypeRaw.isEmpty ? string("type") : timerTypeRaw,
            value: string("value"),
            name: string("name"),
            ingredientId: string("ingredientId"),
            originalAmount: string("originalAmount"),
            ratio: string("ratio"),
            text: string("text"),
            anchorX: cgFloat("anchorX"),
            anchorY: cgFloat("anchorY"),
            anchorWidth: cgFloat("anchorWidth"),
            anchorHeight: cgFloat("anchorHeight")
        )
    }
}
