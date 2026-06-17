//
//  TimerAccessoryCircularView.swift
//  HomeWidgetExtension
//
//  Spec 030 — Lock Screen / StandBy `accessoryCircular` (~52×52).
//  Figma `107:332` monochrome: scaled `WidgetTimerRing`, `.primary` palette,
//  `.widgetAccentable()` for Lock Screen tint.
//

import SwiftUI
import WidgetKit
import RecipeScalerCore

struct TimerAccessoryCircularView: View {
    let entry: TimerWidgetEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Figma accessory circular cell (~52pt) vs home ring path (56pt).
    private static let ringDisplaySize: CGFloat = 52

    private var palette: WidgetTimerPalette {
        WidgetTimerPalette(
            accent: .normal,
            widgetRenderingMode: renderingMode,
            widgetFamily: family
        )
    }

    var body: some View {
        if let first = entry.timers.first {
            content(for: first)
        } else {
            emptyState
        }
    }

    private func content(for timer: TimerSnapshot) -> some View {
        WidgetTimerRing(
            timer: timer,
            now: entry.date,
            palette: palette,
            digitSize: 13
        )
        .scaleEffect(Self.ringDisplaySize / WidgetTimerLayout.ringTrackSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetAccentable()
    }

    private var emptyState: some View {
        Text("—")
            .widgetMono(15)
            .widgetAccentable()
    }
}
