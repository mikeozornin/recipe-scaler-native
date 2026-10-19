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
        if state.phase == .paused {
            Text(TimerLiveActivityFormatting.formatTime(seconds: state.pausedRemainingSeconds))
        } else if let endDate = state.endDate {
            if state.isOverdue() {
                // Counts up past the end on its own, like the Lock Screen card.
                HStack(spacing: 0) {
                    Text("-")
                    Text(
                        timerInterval: endDate...endDate.addingTimeInterval(
                            TimerLockScreenLiveActivityView.overdueHorizon
                        ),
                        countsDown: false
                    )
                }
            } else {
                // `min` keeps the range valid if the end passes between the overdue check and here.
                Text(timerInterval: min(Date(), endDate)...endDate, countsDown: true)
            }
        } else {
            Text(TimerLiveActivityFormatting.formatTime(seconds: state.remainingSeconds()))
        }
    }
}
