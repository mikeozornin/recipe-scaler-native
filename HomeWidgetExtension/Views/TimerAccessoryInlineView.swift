//
//  TimerAccessoryInlineView.swift
//  HomeWidgetExtension
//
//  Spec 030 — Lock Screen / StandBy `accessoryInline` (single line above the date).
//  Figma `107:332` monochrome: `compactRemaining — name` in Martian Mono.
//

import SwiftUI
import WidgetKit
import RecipeScalerCore

struct TimerAccessoryInlineView: View {
    let entry: TimerWidgetEntry

    var body: some View {
        if let first = entry.timers.first {
            content(for: first)
        } else {
            Text("widgets.timer.empty")
                .widgetMono(15)
        }
    }

    @ViewBuilder
    private func content(for timer: TimerSnapshot) -> some View {
        let name = timer.recipeName ?? timer.name
        Group {
            switch timer.phase {
            case .running, .exceeded:
                Text(
                    "\(WidgetTimerFormatting.compactRemaining(seconds: timer.remainingSeconds(now: entry.date))) — \(name)"
                )
                .widgetMono(15)
                .widgetTimerTracking()

            case .paused:
                if let remaining = timer.pausedRemainingSeconds {
                    Text("II \(WidgetTimerFormatting.shortClock(remaining)) — \(name)")
                        .widgetMono(15)
                        .widgetTimerTracking()
                } else {
                    Text("II --:-- — \(name)")
                        .widgetMono(15)
                        .widgetTimerTracking()
                }
            }
        }
        .widgetAccentable()
    }
}
