//
//  AppMotion.swift
//  RecipeScalerNative
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Shared animation curves. Use these instead of a literal duration, so the same kind of
/// change moves the same way on every screen.
enum AppMotion {
    /// Small in-place changes: a check mark, a row in a picker. 0.15 s.
    static let quick: Animation = .easeInOut(duration: 0.15)
    /// Panels, banners and rows that open, close, appear or leave. 0.25 s.
    static let standard: Animation = .easeInOut(duration: 0.25)
    /// Content landing in place: rolled numbers, an inline error. Strong ease-out, 0.2 s.
    static let enter: Animation = .timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
}

/// One feel for every check mark in the app: a light impact when a mark is set, a selection
/// tick when it is taken back. Generators are created once instead of on every tap.
@MainActor
enum CheckToggleHaptics {
    #if os(iOS)
    private static let selection = UISelectionFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let checkIntensity: CGFloat = 0.7
    #endif

    /// `checked` is the state after the tap.
    static func play(checked: Bool) {
        #if os(iOS)
        if checked {
            impact.impactOccurred(intensity: checkIntensity)
        } else {
            selection.selectionChanged()
        }
        #endif
    }
}
