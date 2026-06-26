//
//  TimerFonts.swift
//  RecipeScalerCore
//
//  Spec 039 — Martian typeface helpers shared between watch and other
//  non-widget surfaces. Pure SwiftUI — no UIKit (so it links on watchOS).
//
//  The widget keeps its own `WidgetFonts` (in `HomeWidgetExtension`) because
//  it also exposes `UIFont` / `NSAttributedString` for WidgetKit rendering.
//

import SwiftUI

public enum TimerFonts {
    public static let sans = "Martian Grotesk Nr Lt"
    public static let sansMedium = "Martian Grotesk Nr Md"
    public static let mono = "Martian Mono Nr Lt"

    /// Figma timer digit tracking (−0.1).
    public static let timerTracking: CGFloat = -0.1

    public static func sansFont(size: CGFloat) -> Font {
        .custom(sans, size: size)
    }

    public static func sansMediumFont(size: CGFloat) -> Font {
        .custom(sansMedium, size: size)
    }

    public static func monoFont(size: CGFloat) -> Font {
        .custom(mono, size: size).monospacedDigit()
    }
}

extension Text {
    /// Martian Grotesk Light — keeps `Text` type for multiline layout.
    public func timerSans(_ size: CGFloat) -> Text {
        font(TimerFonts.sansFont(size: size))
    }

    public func timerSansMedium(_ size: CGFloat) -> Text {
        font(TimerFonts.sansMediumFont(size: size))
    }

    public func timerMono(_ size: CGFloat) -> Text {
        font(TimerFonts.monoFont(size: size))
    }

    /// Figma timer digit tracking (−0.1).
    public func timerDigitTracking() -> Text {
        tracking(TimerFonts.timerTracking)
    }
}

extension View {
    /// Martian Grotesk Light at the given size.
    public func timerSans(_ size: CGFloat) -> some View {
        font(TimerFonts.sansFont(size: size))
    }

    public func timerSansMedium(_ size: CGFloat) -> some View {
        font(TimerFonts.sansMediumFont(size: size))
    }

    /// Martian Mono Light at the given size, with monospaced digits for stable countdowns.
    public func timerMono(_ size: CGFloat) -> some View {
        font(TimerFonts.monoFont(size: size))
    }

    /// Figma timer digit tracking (−0.1).
    public func timerDigitTracking() -> some View {
        tracking(TimerFonts.timerTracking)
    }
}
