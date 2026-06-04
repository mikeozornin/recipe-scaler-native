//
//  DescriptionTimerPopoverState.swift
//  RecipeScalerNative
//

import CoreGraphics

/// Anchored timer start popover (global screen coordinates from UITextView).
struct DescriptionTimerPopoverState: Equatable {
    let reference: RecipeDescriptionTimerReference
    let anchor: CGRect
}