//
//  TimerLiveActivityWidget.swift
//  TimerLiveActivityExtension
//

import ActivityKit
import SwiftUI
import WidgetKit

struct TimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecipeTimerActivityAttributes.self) { context in
            TimerLockScreenLiveActivityView(
                attributes: context.attributes,
                state: context.state
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.timerName)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    compactTimerText(state: context.state)
                        .font(.caption.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                compactTimerText(state: context.state)
                    .font(.custom("Martian Mono Nr Lt", size: 12).monospacedDigit())
            } minimal: {
                Image(systemName: "timer")
            }
        }
        .contentMarginsDisabled()
    }

    @ViewBuilder
    private func compactTimerText(state: RecipeTimerActivityAttributes.ContentState) -> some View {
        switch state.phase {
        case .running:
            if let endDate = state.endDate {
                Text(timerInterval: Date()...endDate, countsDown: true)
            } else {
                Text(TimerLiveActivityFormatting.formatTime(seconds: state.remainingSeconds()))
            }
        case .paused:
            Text(TimerLiveActivityFormatting.formatTime(seconds: state.pausedRemainingSeconds))
        case .exceeded:
            Text(TimerLiveActivityFormatting.formatTime(seconds: state.remainingSeconds()))
        }
    }
}
