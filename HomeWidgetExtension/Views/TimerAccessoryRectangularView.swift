//
//  TimerAccessoryRectangularView.swift
//  HomeWidgetExtension
//
//  Spec 030 — Lock Screen / StandBy `accessoryRectangular` (~160×72).
//  Figma `107:332` monochrome: name + compact/live countdown (Martian Mono).
//

import SwiftUI
import WidgetKit
import RecipeScalerCore

struct TimerAccessoryRectangularView: View {
    let entry: TimerWidgetEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

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
        VStack(alignment: .leading, spacing: 1) {
            Text(timer.recipeName ?? timer.name)
                .widgetMono(12)
                .foregroundStyle(palette.timerColor)
                .lineLimit(1)
            countdownLabel(for: timer)
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func countdownLabel(for timer: TimerSnapshot) -> some View {
        switch timer.phase {
        case .running, .exceeded:
            Text(WidgetTimerFormatting.compactRemaining(seconds: timer.remainingSeconds(now: entry.date)))
                .widgetMono(14)
                .widgetTimerTracking()
                .foregroundStyle(palette.timerColor)

        case .paused:
            if let remaining = timer.pausedRemainingSeconds {
                Text("II \(WidgetTimerFormatting.shortClock(remaining))")
                    .widgetMono(14)
                    .widgetTimerTracking()
                    .foregroundStyle(palette.timerColor)
            } else {
                Text("II --:--")
                    .widgetMono(14)
                    .widgetTimerTracking()
                    .foregroundStyle(palette.timerColor)
            }
        }
    }

    private var emptyState: some View {
        Text("widgets.timer.empty")
            .widgetMono(12)
            .widgetAccentable()
    }
}
