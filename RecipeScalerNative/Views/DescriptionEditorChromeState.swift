//
//  DescriptionEditorChromeState.swift
//  RecipeScalerNative
//
//  Observable chrome for inline editor toolbar (019).
//

import Foundation

@MainActor
@Observable
final class DescriptionEditorChromeState {
    private(set) var suppressFormattingBar = false
    private(set) var bridge: DescriptionEditorBridge?

    init() {}

    /// Formatting bar only when the description field is actively focused and no modal chrome is open.
    /// Reads directly from the (already @Observable) `bridge` — observation is automatic.
    var showsFormattingBar: Bool {
        guard let bridge else { return false }
        return bridge.phase == .ready && bridge.isFocused && !suppressFormattingBar
    }

    /// Whether the description editor is currently focused. Mirrors `bridge.isFocused`.
    var isFocused: Bool {
        bridge?.isFocused ?? false
    }

    /// Whether the description editor has finished loading. Mirrors `bridge.phase == .ready`.
    var isEditorReady: Bool {
        bridge?.phase == .ready
    }

    /// One-time bind. Once `bridge` is set, all state reads derive from it via Observation.
    func bind(bridge: DescriptionEditorBridge) {
        guard self.bridge !== bridge else { return }
        self.bridge = bridge
    }

    func reset() {
        bridge = nil
        suppressFormattingBar = false
    }

    func setSuppressFormattingBar(_ suppress: Bool) {
        guard suppressFormattingBar != suppress else { return }
        suppressFormattingBar = suppress
    }

    func blurEditor() {
        if let bridge {
            bridge.dismissEditingFocus()
        }
    }
}
