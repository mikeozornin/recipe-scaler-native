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
        let hasBridge = bridge != nil
        let phaseReady = bridge?.phase == .ready
        let focused = bridge?.isFocused ?? false
        let suppressed = suppressFormattingBar
        let result = hasBridge && phaseReady && focused && !suppressed
        // #region agent log
        DebugModeLog.write(
            "showsFormattingBar evaluated",
            hypothesisId: "H1",
            data: [
                "result": result ? "true" : "false",
                "hasBridge": hasBridge ? "true" : "false",
                "phaseReady": phaseReady ? "true" : "false",
                "focused": focused ? "true" : "false",
                "suppressed": suppressed ? "true" : "false",
            ]
        )
        // #endregion
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
        let wasNil = self.bridge == nil
        // #region agent log
        DebugModeLog.write(
            "bind(bridge:) called",
            hypothesisId: "H2",
            data: [
                "wasNil": wasNil ? "true" : "false",
                "sameInstance": (self.bridge === bridge) ? "true" : "false",
            ]
        )
        // #endregion
        guard self.bridge !== bridge else { return }
        self.bridge = bridge
    }

    func reset() {
        bridge = nil
        suppressFormattingBar = false
    }

    func setSuppressFormattingBar(_ suppress: Bool) {
        // #region agent log
        DebugModeLog.write(
            "setSuppressFormattingBar",
            hypothesisId: "H5",
            data: [
                "from": suppressFormattingBar ? "true" : "false",
                "to": suppress ? "true" : "false",
            ]
        )
        // #endregion
        guard suppressFormattingBar != suppress else { return }
        suppressFormattingBar = suppress
    }

    func blurEditor() {
        if let bridge {
            bridge.dismissEditingFocus()
        }
    }
}
