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

        // Snapshot current state
        isFocused = bridge.isFocused
        isEditorReady = bridge.phase == .ready

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
