//
//  WidgetTimerLayout.swift
//  HomeWidgetExtension
//
//  Spec 030 — Figma layout tokens for TimerWidget (107:207 / 107:318).
//

import CoreGraphics

enum WidgetTimerLayout {
    static let padding: CGFloat = 16
    static let gridGap: CGFloat = 12
    static let contentSize: CGFloat = 169 - padding * 2

    // Ring — center stroke: 56pt path + 6pt stroke ≈ 62pt outer (Figma cell).
    static let ringTrackSize: CGFloat = 56
    static let ringStrokeWidth: CGFloat = 6

    // Linear row (2 timers — full content width)
    static let linearBarHeight: CGFloat = 4
    static let linearTrackHeight: CGFloat = 2
    static let linearFillHeight: CGFloat = 2
    static let linearBarToTimeGap: CGFloat = 8
    static let linearTimeWidth: CGFloat = 40
    /// Bar track width: content − gap − time column (137 − 8 − 40 = 89).
    static let linearBarMaxWidth: CGFloat =
        contentSize - linearBarToTimeGap - linearTimeWidth
    static let linearTimeLineHeight: CGFloat = 16
    /// Lifts compact time above the 4pt bar without growing the row (Figma 107:318).
    static let linearTimeOffsetY: CGFloat = -7.5
    static let linearNameMaxWidth: CGFloat = contentSize
    static let linearNameLineHeight: CGFloat = 18
    static let linearNameMaxLines: Int = 3
    static let linearRowSpacing: CGFloat = 4
    /// 3 lines × 18pt — same budget as 1-timer label block.
    static let twoTimerLabelHeight: CGFloat =
        CGFloat(linearNameMaxLines) * linearNameLineHeight
    /// Bar (4) + gap (4) + label (54) = 62pt; two rows + 12pt gap = 136 ≤ 137.
    static let twoTimerRowHeight: CGFloat =
        linearBarHeight + linearRowSpacing + twoTimerLabelHeight

    /// Ring row + gap + 3 label lines = 56 + 12 + 54 = 122 ≤ 137 content height.
    static let singleTimerLabelBlockHeight: CGFloat =
        CGFloat(linearNameMaxLines) * linearNameLineHeight

    // Typography
    static let ringDigitSizeSingle: CGFloat = 14
    static let ringDigitSizeMulti: CGFloat = 15
    static let ringDigitLineHeight: CGFloat = 18
    static let linearTimeSize: CGFloat = 15
    static let linearNameSize: CGFloat = 15
    static let tracking: CGFloat = WidgetFonts.timerTracking
}
