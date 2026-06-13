//
//  DescriptionEditorChromeState.swift
//  RecipeScalerNative
//
//  Observable chrome for inline editor toolbar (019).
//

import Combine
import Foundation

@MainActor
final class DescriptionEditorChromeState: ObservableObject {
    @Published private(set) var isFocused = false
    @Published private(set) var isEditorReady = false
    @Published private(set) var suppressFormattingBar = false
    private(set) var bridge: DescriptionEditorBridge?

    private var cancellables = Set<AnyCancellable>()

    /// Formatting bar only when the description field is actively focused and no modal chrome is open.
    var showsFormattingBar: Bool {
        bridge != nil && isEditorReady && isFocused && !suppressFormattingBar
    }

    /// One-time bind: subscribe to bridge publishers so chrome stays in sync automatically.
    func bind(bridge: DescriptionEditorBridge) {
        guard self.bridge !== bridge else { return }
        self.bridge = bridge
        cancellables.removeAll()

        // Defer the initial @Published snapshot to the next runloop tick. `bind` is
        // typically called from `.onAppear`, which runs synchronously during the SwiftUI
        // body / layout pass; mutating `@Published` here triggers
        // "Publishing changes from within view updates is not allowed".
        let initialFocused = bridge.isFocused
        let initialReady = bridge.phase == .ready
        DispatchQueue.main.async { [weak self] in
            self?.isFocused = initialFocused
            self?.isEditorReady = initialReady
        }

        // Subscribe to future changes — single source of truth
        bridge.$isFocused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] focused in
                self?.isFocused = focused
            }
            .store(in: &cancellables)

        bridge.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.isEditorReady = phase == .ready
            }
            .store(in: &cancellables)
    }

    func reset() {
        bridge = nil
        cancellables.removeAll()
        isFocused = false
        isEditorReady = false
        suppressFormattingBar = false
    }

    func setSuppressFormattingBar(_ suppress: Bool) {
        guard suppressFormattingBar != suppress else { return }
        suppressFormattingBar = suppress
    }

    func blurEditor() {
        isFocused = false
        if let bridge {
            bridge.dismissEditingFocus()
        }
    }
}
