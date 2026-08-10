//
//  InteractionProfile.swift
//  RecipeScalerNative
//
//  Spec 043 — touch (iOS) vs pointer (macOS) row affordances.
//

import Foundation
import SwiftUI

enum InteractionProfile: Equatable {
    case touch
    case pointer

    static var current: InteractionProfile {
        #if os(macOS)
        return .pointer
        #else
        return .touch
        #endif
    }
}

/// State machine shared by pointer-profile row adapters.
///
/// A horizontal trackpad gesture can reveal one action strip at a time. The
/// pointer must pass through the neutral state before the opposite strip can
/// open; this mirrors the web DesktopScrollableRow contract and prevents one
/// continuous gesture from jumping directly from leading to trailing actions.
enum PointerActionStrip: Equatable {
    case none
    case leading
    case trailing
}

struct TrackpadActionStripState: Equatable {
    private(set) var strip: PointerActionStrip = .none
    private var armedDirection: PointerActionStrip = .none

    mutating func consume(deltaX: CGFloat) {
        guard deltaX.isFinite else {
            reset()
            return
        }

        let nextDirection: PointerActionStrip
        if deltaX > 8 {
            nextDirection = .leading
        } else if deltaX < -8 {
            nextDirection = .trailing
        } else {
            reset()
            return
        }

        guard armedDirection == .none else { return }
        strip = nextDirection
        armedDirection = nextDirection
    }

    mutating func reset() {
        strip = .none
        armedDirection = .none
    }
}

private struct InteractionProfileKey: EnvironmentKey {
    static let defaultValue: InteractionProfile = .touch
}

extension EnvironmentValues {
    var interactionProfile: InteractionProfile {
        get { self[InteractionProfileKey.self] }
        set { self[InteractionProfileKey.self] = newValue }
    }
}
