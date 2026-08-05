//
//  TimerLockScreenLiveActivityView.swift
//  TimerLiveActivityExtension
//

import ActivityKit
import SwiftUI
import WidgetKit
import RecipeScalerCore

struct TimerLockScreenLiveActivityView: View {
    let attributes: RecipeTimerActivityAttributes
    let state: RecipeTimerActivityAttributes.ContentState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground

    private static let overdueHorizon: TimeInterval = 24 * 60 * 60
    private static let progressBarHeight: CGFloat = 8
    private static let appGroupIdentifier = AppGroup.id

    private static let timerDigitsFont = Font.custom("Martian Mono Nr Lt", size: 40)
    private static let timerNameFont = Font.custom("Martian Grotesk Nr Md", size: 16)

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
        let resolvedAccent = TimerLiveActivityPalette.accentColor(
            for: accent,
            colorScheme: colorScheme,
            isLuminanceReduced: isLuminanceReduced,
            widgetRenderingMode: widgetRenderingMode,
            showsWidgetContainerBackground: showsWidgetContainerBackground
        )
        let fillColor: Color = overdue
            ? TimerLiveActivityPalette.accentColor(
                for: .exceeded,
                colorScheme: colorScheme,
                isLuminanceReduced: isLuminanceReduced,
                widgetRenderingMode: widgetRenderingMode,
                showsWidgetContainerBackground: showsWidgetContainerBackground
            )
            : resolvedAccent
        let primaryTextColor: Color = overdue
            ? TimerLiveActivityPalette.accentColor(
                for: .exceeded,
                colorScheme: colorScheme,
                isLuminanceReduced: isLuminanceReduced,
                widgetRenderingMode: widgetRenderingMode,
                showsWidgetContainerBackground: showsWidgetContainerBackground
            )
            : resolvedAccent
        let labelColor = TimerLiveActivityPalette.labelColor(
            colorScheme: colorScheme,
            isLuminanceReduced: isLuminanceReduced,
            widgetRenderingMode: widgetRenderingMode,
            showsWidgetContainerBackground: showsWidgetContainerBackground
        )

        VStack(alignment: .leading, spacing: 0) {
            lockScreenProgressBar(fillColor: fillColor, overdue: overdue)

            VStack(alignment: .leading, spacing: 12) {
                timerNameRow(
                    resolvedAccentColor: resolvedAccent,
                    primaryTextColor: primaryTextColor,
                    overdue: overdue
                )

                if attributes.recipeId != nil || state.recipeName != nil {
                    recipeRow(labelColor: labelColor)
                }
            }
            .padding(14)
        }
        .widgetURL(attributes.recipeId.flatMap { URL(string: "recipe-scaler://recipe/\($0)") })
        .activitySystemActionForegroundColor(labelColor)
        // Fixed dark card chrome + light foreground for every appearance.
        // See `dim-live-activity.md`: the widget extension process can resolve
        // `\.colorScheme` as stale `.light` on the Lock Screen (FB15148099), and
        // DND/Focus-dim does NOT flip `\.isLuminanceReduced` — so the system
        // would otherwise paint a light card background in Light Mode and a dim
        // one in Focus. We pin both surfaces explicitly to keep the contrast.
        .activityBackgroundTint(.black)
        .containerBackground(Color.black, for: .widget)
    }

    // MARK: - Timer row (Figma: timer + control on top, name below)

    @ViewBuilder
    private func timerNameRow(
        resolvedAccentColor: Color,
        primaryTextColor: Color,
        overdue: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                lockScreenTimerDigits(color: primaryTextColor, overdue: overdue)

                Spacer(minLength: 0)

                if !overdue {
                    lockScreenControlButton(accentColor: resolvedAccentColor)
                }
            }

            Text(attributes.timerName)
                .font(Self.timerNameFont)
                .foregroundStyle(primaryTextColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func lockScreenTimerDigits(color: Color, overdue: Bool) -> some View {
        if state.phase == .paused {
            Text(TimerLiveActivityFormatting.formatTime(seconds: state.pausedRemainingSeconds))
                .font(Self.timerDigitsFont)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if isLuminanceReduced {
            // AOD / dimmed lock screen: system Text(timerInterval:) hides seconds as
            // "44 : --". Show widget-style compact "44m" / "-44m" instead.
            Text(TimerFormatting.compactRemaining(seconds: state.remainingSeconds()))
                .font(Self.timerDigitsFont)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if overdue, let endDate = state.endDate {
            HStack(spacing: 0) {
                Text("-")
                Text(
                    timerInterval: endDate...endDate.addingTimeInterval(Self.overdueHorizon),
                    countsDown: false
                )
            }
            .font(Self.timerDigitsFont)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else if let endDate = state.endDate {
            Text(timerInterval: Date()...endDate, countsDown: true)
                .font(Self.timerDigitsFont)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Text(TimerLiveActivityFormatting.formatTime(seconds: state.remainingSeconds()))
                .font(Self.timerDigitsFont)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private func lockScreenControlButton(accentColor: Color) -> some View {
        if state.phase == .paused {
            Button(intent: ResumeRecipeTimerIntent(timerId: attributes.timerId)) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        } else {
            Button(intent: PauseRecipeTimerIntent(timerId: attributes.timerId)) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private func recipeRow(labelColor: Color) -> some View {
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
                    .foregroundStyle(
                        TimerLiveActivityPalette.secondaryLabelColor(
                            colorScheme: colorScheme,
                            isLuminanceReduced: isLuminanceReduced,
                            widgetRenderingMode: widgetRenderingMode
                        )
                    )
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Progress bar

    @ViewBuilder
    private func lockScreenProgressBar(fillColor: Color, overdue: Bool) -> some View {
        Rectangle()
            .fill(
                TimerLiveActivityPalette.progressTrackColor(
                    colorScheme: colorScheme,
                    isLuminanceReduced: isLuminanceReduced,
                    widgetRenderingMode: widgetRenderingMode
                )
            )
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
