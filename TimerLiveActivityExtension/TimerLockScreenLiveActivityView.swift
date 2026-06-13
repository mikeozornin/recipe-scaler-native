//
//  TimerLockScreenLiveActivityView.swift
//  TimerLiveActivityExtension
//

import ActivityKit
import SwiftUI
import WidgetKit

struct TimerLockScreenLiveActivityView: View {
    let attributes: RecipeTimerActivityAttributes
    let state: RecipeTimerActivityAttributes.ContentState

    private static let overdueHorizon: TimeInterval = 24 * 60 * 60
    private static let progressBarHeight: CGFloat = 8
    private static let appGroupIdentifier = "group.ru.recipescaler.RecipeScalerNative"

    private static func loadThumbnail(name: String) -> UIImage? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let url = container.appendingPathComponent("la-thumbs/\(name)")
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        let accent = TimerLiveActivityAccent.resolve(
            remainingSeconds: state.remainingSeconds(),
            totalDuration: state.totalDuration
        )
        let overdue = state.phase == .exceeded
        let fillColor: Color = overdue
            ? TimerLiveActivityPalette.accentColor(for: .exceeded)
            : accent.progressFillColor

        VStack(alignment: .leading, spacing: 0) {
            lockScreenProgressBar(fillColor: fillColor, overdue: overdue)

            // Content
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    // Timer digits
                    if state.phase == .paused {
                        Text(TimerLiveActivityFormatting.formatTime(seconds: state.pausedRemainingSeconds))
                            .font(.custom("Martian Mono Nr Lt", size: 40).monospacedDigit())
                            .foregroundStyle(accent.color)
                    } else if overdue, let endDate = state.endDate {
                        HStack(spacing: 0) {
                            Text("-")
                            Text(timerInterval: endDate...endDate.addingTimeInterval(Self.overdueHorizon), countsDown: false)
                        }
                        .font(.custom("Martian Mono Nr Lt", size: 40).monospacedDigit())
                        .foregroundStyle(TimerLiveActivityPalette.accentColor(for: .exceeded))
                    } else if let endDate = state.endDate {
                        Text(timerInterval: Date()...endDate, countsDown: true)
                            .font(.custom("Martian Mono Nr Lt", size: 40).monospacedDigit())
                            .foregroundStyle(accent.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text(TimerLiveActivityFormatting.formatTime(seconds: state.remainingSeconds()))
                            .font(.custom("Martian Mono Nr Lt", size: 40).monospacedDigit())
                            .foregroundStyle(accent.color)
                    }

                    Text(attributes.timerName)
                        .font(.custom("Martian Grotesk Nr Md", size: overdue ? 24 : 16))
                        .foregroundStyle(overdue ? TimerLiveActivityPalette.accentColor(for: .exceeded) : accent.color)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !overdue && state.phase == .paused {
                        Button(intent: ResumeRecipeTimerIntent(timerId: attributes.timerId)) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(accent.color)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    } else if !overdue {
                        Button(intent: PauseRecipeTimerIntent(timerId: attributes.timerId)) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(accent.color)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Recipe row
                if attributes.recipeId != nil || state.recipeName != nil {
                    HStack(spacing: 10) {
                        if let thumbName = state.recipeThumbnailName,
                           let uiImage = Self.loadThumbnail(name: thumbName) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        } else {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        if let recipeName = state.recipeName, !recipeName.isEmpty {
                            Text(recipeName)
                                .font(.system(size: 14))
                                .foregroundStyle(TimerLiveActivityPalette.secondaryLabel)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(14)
        }
        .widgetURL(attributes.recipeId.flatMap { URL(string: "recipe-scaler://recipe/\($0)") })
        .activitySystemActionForegroundColor(TimerLiveActivityPalette.label)
    }

    @ViewBuilder
    private func lockScreenProgressBar(fillColor: Color, overdue: Bool) -> some View {
        // Same footprint as diagnostic `Rectangle().fill(Color.red).frame(height: 8)`:
        // full-width 8pt track, leading fill in palette colors.
        Rectangle()
            .fill(TimerLiveActivityPalette.progressTrack)
            .overlay(alignment: .leading) {
                progressFill(fillColor: fillColor, overdue: overdue)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.progressBarHeight)
            .clipped()
    }

    @ViewBuilder
    private func progressFill(fillColor: Color, overdue: Bool) -> some View {
        if state.phase == .running, !overdue, let endDate = state.endDate {
            ProgressView(
                timerInterval: state.startedAt...endDate,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(
                TimerLiveActivityLinearProgressStyle(
                    fillColor: fillColor,
                    barHeight: Self.progressBarHeight
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: Self.progressBarHeight)
        } else {
            Rectangle()
                .fill(fillColor)
                .scaleEffect(
                    x: max(0, min(1, elapsedProgress(overdue: overdue))),
                    y: 1,
                    anchor: .leading
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func elapsedProgress(overdue: Bool) -> Double {
        if state.phase == .paused {
            guard state.totalDuration > 0 else { return 0 }
            return min(1, max(0, (state.totalDuration - Double(state.pausedRemainingSeconds)) / state.totalDuration))
        }
        if overdue { return 1 }
        return state.progress
    }
}
