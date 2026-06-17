//
//  TimerWidgetKind.swift
//  RecipeScalerCore
//
//  Shared WidgetKit kind identifier for `TimerWidget`.
//  Referenced by both the main app (when calling `WidgetCenter.reloadTimelines`)
//  and `HomeWidgetExtension` (in `StaticConfiguration(kind:)`).
//

import Foundation

public enum TimerWidgetKind {
    public static let id = "TimerWidget"
}
