//
//  DescriptionEditorChromeState.swift
//  RecipeScalerNative
//
//  Observable chrome for inline editor toolbar (019).
//

import Foundation

@MainActor
final class DescriptionEditorChromeState: ObservableObject {
    @Published private(set) var isFocused = false
    @Published private(set) var isEditorReady = false
    private(set) var bridge: DescriptionEditorBridge?

    /// Native formatting bar visible only when the editor is focused.
    var showsFormattingBar: Bool {
        bridge != nil && isEditorReady && isFocused
    }

    func bind(bridge: DescriptionEditorBridge) {
        self.bridge = bridge
        isFocused = bridge.isFocused
        isEditorReady = bridge.phase == .ready
    }

    func syncFocus(_ focused: Bool) {
        guard isFocused != focused else { return }
        isFocused = focused
    }

    func syncPhase(_ phase: DescriptionEditorBridge.Phase) {
        isEditorReady = phase == .ready
    }

    func reset() {
        bridge = nil
        isFocused = false
        isEditorReady = false
    }
}
