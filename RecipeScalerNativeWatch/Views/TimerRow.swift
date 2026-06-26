//
//  TimerRow.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — single timer row in the watch List. Reuses Core primitives
//  where possible; the watch row additionally shows an action icon that
//  reflects the *action* (pause / resume), not the status.
//

import SwiftUI
import RecipeScalerCore

struct TimerRow: View {
    let timer: WatchTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            nameLabel
        }
        .frame(maxWidth: .infinity, minHeight: WatchTimerLayout.rowMinHeight, alignment: .topLeading)
    }

    private var topRow: some View {
        HStack(spacing: WatchTimerLayout.actionToProgressSpacing) {
            actionIcon
            progressBar
            timeLabel
                .frame(width: WatchTimerLayout.timeColumnWidth, alignment: .trailing)
        }
        .frame(height: WatchTimerLayout.topRowHeight)
    }

    private var actionIcon: some View {
        Image(systemName: timer.actionIcon)
            .font(.system(size: WatchTimerLayout.actionIconSize, weight: .medium))
            .foregroundStyle(paletteColor)
            .frame(width: WatchTimerLayout.actionIconSize, height: WatchTimerLayout.topRowHeight)
            .accessibilityHidden(true)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(paletteColor.opacity(TimerPalette.trackOpacity))
                    .frame(width: geo.size.width, height: WatchTimerLayout.progressTrackHeight)
                Rectangle()
                    .fill(paletteColor)
                    .frame(
                        width: geo.size.width * timer.progressFraction,
                        height: WatchTimerLayout.progressFillHeight
                    )
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: WatchTimerLayout.progressTrackHeight)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var timeLabel: some View {
        if timer.isPaused, let remaining = timer.pausedRemainingSeconds {
            Text(TimerFormatting.shortClock(remaining))
                .timerMono(WatchTimerLayout.timeFontSize)
                .timerDigitTracking()
                .foregroundStyle(paletteColor)
                .lineLimit(1)
        } else if let endDate = timer.endDate {
            // Live countdown — system-driven via `Text(timerInterval:)`.
            Text(timerInterval: Date()...endDate, countsDown: true)
                .timerMono(WatchTimerLayout.timeFontSize)
                .timerDigitTracking()
                .foregroundStyle(paletteColor)
                .lineLimit(1)
                .monospacedDigit()
        } else {
            Text(TimerFormatting.compactRemaining(seconds: timer.remainingSeconds(now: Date())))
                .timerMono(WatchTimerLayout.timeFontSize)
                .timerDigitTracking()
                .foregroundStyle(paletteColor)
                .lineLimit(1)
        }
    }

    private var nameLabel: some View {
        Text(timer.name)
            .timerSans(WatchTimerLayout.nameFontSize)
            .foregroundStyle(paletteColor)
            .lineLimit(WatchTimerLayout.nameMaxLines)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var paletteColor: Color {
        TimerPalette.resolve(
            phase: timer.isPaused ? .paused : .running,
            remainingSeconds: timer.remainingSeconds(now: Date()),
            totalDuration: TimeInterval(timer.duration)
        ).color
    }
}

#Preview("TimerRow — running") {
    TimerRow(
        timer: WatchTimer(
            server: .init(
                timerId: "t1",
                name: "до золотой корочки",
                duration: 1800,
                endTime: Int64((Date().addingTimeInterval(900)).timeIntervalSince1970 * 1000),
                isPaused: false,
                pausedDuration: nil,
                createdAt: 0,
                lastUpdated: 0,
                startedAt: 0,
                pausedAt: nil,
                recipeId: nil
            )
        )
    )
    .frame(width: 179)
}
