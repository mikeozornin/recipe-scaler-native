//
//  TimerRow.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — single timer row in the watch List. Pause/resume/delete via
//  swipe actions only (no leading action icon in the row).
//
//  `now` is supplied by the parent `TimelineView` in `TimerListView` so the
//  progress bar and countdown tick inside `List` on watchOS (TimelineView
//  inside a row does not reliably schedule updates).
//

import SwiftUI
import RecipeScalerCore

struct TimerRow: View {
    let timer: WatchTimer
    let now: Date

    var body: some View {
        rowContent(now: now)
            .frame(maxWidth: .infinity, minHeight: WatchTimerLayout.rowMinHeight, alignment: .topLeading)
    }

    private func rowContent(now: Date) -> some View {
        let palette = timer.palette(at: now)
        let accentColor = palette.color
        let fraction = timer.progressFraction(now: now)
        let remaining = timer.remainingSeconds(now: now)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WatchTimerLayout.progressToTimeSpacing) {
                progressBar(fraction: fraction, color: accentColor, tick: remaining)
                timeLabel(seconds: remaining, color: accentColor)
                    .frame(minWidth: WatchTimerLayout.timeColumnWidth, alignment: .trailing)
            }
            .frame(height: WatchTimerLayout.topRowHeight)

            nameLabel(color: accentColor)
        }
        .foregroundStyle(accentColor)
    }

    private func timeLabel(seconds: Int, color: Color) -> some View {
        Text(TimerFormatting.compactRemaining(seconds: seconds))
            .font(TimerFonts.monoFont(size: WatchTimerLayout.timeFontSize))
            .tracking(TimerFonts.timerTracking)
            .foregroundStyle(color)
            .lineLimit(1)
            .monospacedDigit()
    }

    private func progressBar(fraction: Double, color: Color, tick: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(color.opacity(TimerPalette.trackOpacity))
                    .frame(width: geo.size.width, height: WatchTimerLayout.progressTrackHeight)
                Rectangle()
                    .fill(color)
                    .frame(
                        width: geo.size.width * fraction,
                        height: WatchTimerLayout.progressFillHeight
                    )
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: WatchTimerLayout.progressTrackHeight)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        // Tie layout to the countdown second so List rows redraw the fill width.
        .id(tick)
    }

    private func nameLabel(color: Color) -> some View {
        Text(timer.name)
            .font(TimerFonts.sansFont(size: WatchTimerLayout.nameFontSize))
            .foregroundStyle(color)
            .lineLimit(WatchTimerLayout.nameMaxLines)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
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
        ),
        now: Date()
    )
    .frame(width: 179)
}

#Preview("TimerRow — exceeded") {
    TimerRow(
        timer: WatchTimer(
            server: .init(
                timerId: "t2",
                name: "10 секунд",
                duration: 10,
                endTime: Int64((Date().addingTimeInterval(-480)).timeIntervalSince1970 * 1000),
                isPaused: false,
                pausedDuration: nil,
                createdAt: 0,
                lastUpdated: 0,
                startedAt: 0,
                pausedAt: nil,
                recipeId: nil
            )
        ),
        now: Date()
    )
    .frame(width: 179)
}

#Preview("TimerRow — soon") {
    TimerRow(
        timer: WatchTimer(
            server: .init(
                timerId: "t3",
                name: "10 секунд",
                duration: 10,
                endTime: Int64((Date().addingTimeInterval(1)).timeIntervalSince1970 * 1000),
                isPaused: false,
                pausedDuration: nil,
                createdAt: 0,
                lastUpdated: 0,
                startedAt: 0,
                pausedAt: nil,
                recipeId: nil
            )
        ),
        now: Date()
    )
    .frame(width: 179)
}
