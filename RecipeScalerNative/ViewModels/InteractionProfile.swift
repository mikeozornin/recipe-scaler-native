//
//  InteractionProfile.swift
//  RecipeScalerNative
//
//  Spec 043 — touch (iOS) vs pointer (macOS) row affordances.
//

import Foundation

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