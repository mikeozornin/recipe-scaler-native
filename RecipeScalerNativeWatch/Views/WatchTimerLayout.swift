//
//  WatchTimerLayout.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — Figma tokens (node `132:635`) for the watch UI.
//  Single source of truth for sizes — no magic numbers in views.
//

import CoreGraphics

enum WatchTimerLayout {
    /// Content padding from the screen edge.
    static let padding: CGFloat = 16

    /// HIG minimum tap target for any interactive row.
    static let rowMinHeight: CGFloat = 44

    /// Top row (progress + time).
    static let topRowHeight: CGFloat = 24
    static let progressToTimeSpacing: CGFloat = 8

    static let progressTrackHeight: CGFloat = 2
    static let progressFillHeight: CGFloat = 2

    static let timeColumnWidth: CGFloat = 40
    static let timeFontSize: CGFloat = 15
    static let timeLineHeight: CGFloat = 16

    static let nameFontSize: CGFloat = 15
    static let nameLineHeight: CGFloat = 18
    static let nameMaxLines: Int = 5

    /// SF Symbol size for Empty / Error / NotAuthorized icons.
    static let stateIconSize: CGFloat = 48

    /// Spacing between the icon and the title text.
    static let stateStackSpacing: CGFloat = 8

    /// Gap between the state square (icon+text) and the Settings button.
    static let stateToSettingsSpacing: CGFloat = 16

    /// Font size for Empty / Error / NotAuthorized titles (Martian Grotesk).
    static let stateTitleFontSize: CGFloat = 15

    /// Settings row sizing.
    static let settingsHeight: CGFloat = 44
}
