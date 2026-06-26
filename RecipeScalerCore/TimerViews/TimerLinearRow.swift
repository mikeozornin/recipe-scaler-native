//
//  TimerLinearRow.swift
//  RecipeScalerCore
//
//  Spec 039 — watchOS Timers: adaptive row used in the watch app's
//  `TimerListView`. Unlike `WidgetTimerLinearRow` (fixed 137pt width), this
//  view is fully fluid: `maxWidth: .infinity`, `minHeight: 44` (HIG).
//
//  Renders the same Figma layout as the widget row:
//    [action icon] [spacer] [progress bar — flex] [time]
//    [recipe name — full width]
//
//  Action icon is supplied by the caller (watch passes a Button-style icon,
//  since the watch row is interactive — not the case for the widget).
//

import SwiftUI

/// Token set for the watchOS linear row. Kept as a struct so callers can
/// override (e.g. previews with longer names) without magic numbers in views.
public struct TimerLinearRowMetrics: Sendable, Equatable {
    public let topRowHeight: CGFloat
    public let actionIconSize: CGFloat
    public let actionToProgressSpacing: CGFloat
    public let progressTrackHeight: CGFloat
    public let progressFillHeight: CGFloat
    public let timeColumnWidth: CGFloat
    public let timeFontSize: CGFloat
    public let timeLineHeight: CGFloat
    public let nameFontSize: CGFloat
    public let nameLineHeight: CGFloat
    public let nameMaxLines: Int
    public let rowMinHeight: CGFloat
    public let rowSpacing: CGFloat

    public init(
        topRowHeight: CGFloat = 24,
        actionIconSize: CGFloat = 20,
        actionToProgressSpacing: CGFloat = 8,
        progressTrackHeight: CGFloat = 2,
        progressFillHeight: CGFloat = 2,
        timeColumnWidth: CGFloat = 40,
        timeFontSize: CGFloat = 15,
        timeLineHeight: CGFloat = 16,
        nameFontSize: CGFloat = 15,
        nameLineHeight: CGFloat = 18,
        nameMaxLines: Int = 2,
        rowMinHeight: CGFloat = 44,
        rowSpacing: CGFloat = 0
    ) {
        self.topRowHeight = topRowHeight
        self.actionIconSize = actionIconSize
        self.actionToProgressSpacing = actionToProgressSpacing
        self.progressTrackHeight = progressTrackHeight
        self.progressFillHeight = progressFillHeight
        self.timeColumnWidth = timeColumnWidth
        self.timeFontSize = timeFontSize
        self.timeLineHeight = timeLineHeight
        self.nameFontSize = nameFontSize
        self.nameLineHeight = nameLineHeight
        self.nameMaxLines = nameMaxLines
        self.rowMinHeight = rowMinHeight
        self.rowSpacing = rowSpacing
    }

    /// Default metrics matching Figma node `132:635` (watchOS layout).
    public static let watch = TimerLinearRowMetrics()
}

/// Adaptive linear timer row.
///
/// - Parameters:
///   - timer: snapshot to render.
///   - now: anchor date for live countdown.
///   - palette: color palette (resolves `normal` / `soon` / `exceeded`).
///   - metrics: layout tokens (use `.watch` for the watch app).
///   - actionIcon: SF Symbol name rendered at the leading edge. Shows the
///     *action* the user can take (e.g. `pause.fill` on a running timer,
///     `play.fill` on a paused timer), not the status.
public struct TimerLinearRow: View {
    public let timer: TimerSnapshot
    public let now: Date
    public let palette: TimerPalette
    public let metrics: TimerLinearRowMetrics
    public let actionIcon: String

    public init(
        timer: TimerSnapshot,
        now: Date,
        palette: TimerPalette,
        metrics: TimerLinearRowMetrics = .watch,
        actionIcon: String
    ) {
        self.timer = timer
        self.now = now
        self.palette = palette
        self.metrics = metrics
        self.actionIcon = actionIcon
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            topRow
            nameLabel
        }
        .frame(maxWidth: .infinity, minHeight: metrics.rowMinHeight, alignment: .topLeading)
    }

    private var topRow: some View {
        HStack(spacing: metrics.actionToProgressSpacing) {
            Image(systemName: actionIcon)
                .font(.system(size: metrics.actionIconSize, weight: .medium))
                .foregroundStyle(palette.color)
                .frame(width: metrics.actionIconSize, height: metrics.topRowHeight)
                .accessibilityHidden(true)

            progressBar
                .frame(maxWidth: .infinity)

            timeLabel
                .frame(width: metrics.timeColumnWidth, alignment: .trailing)
        }
        .frame(height: metrics.topRowHeight)
    }

    private var progressBar: some View {
        let progress = timer.progressFraction(now: now)
        // GeometryReader is the cleanest SwiftUI way to size the fill as a
        // fraction of the available width. The HStack above bounds our width
        // via `maxWidth: .infinity`; this reader measures that width so the
        // fill is `width * progress` — fully adaptive, no fixed 70pt.
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.color.opacity(TimerPalette.trackOpacity))
                    .frame(width: geo.size.width, height: metrics.progressTrackHeight)
                Rectangle()
                    .fill(palette.color)
                    .frame(width: geo.size.width * progress, height: metrics.progressFillHeight)
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: max(metrics.progressTrackHeight, metrics.progressFillHeight))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var timeLabel: some View {
        switch timer.phase {
        case .running, .exceeded:
            if let endDate = timer.endDate {
                Text(timerInterval: Date()...endDate, countsDown: true)
                    .timerMono(metrics.timeFontSize)
                    .timerDigitTracking()
                    .foregroundStyle(palette.color)
                    .lineLimit(1)
                    .monospacedDigit()
            } else {
                Text(TimerFormatting.compactRemaining(seconds: timer.remainingSeconds(now: now)))
                    .timerMono(metrics.timeFontSize)
                    .timerDigitTracking()
                    .foregroundStyle(palette.color)
                    .lineLimit(1)
            }
        case .paused:
            if let remaining = timer.pausedRemainingSeconds {
                Text(TimerFormatting.shortClock(remaining))
                    .timerMono(metrics.timeFontSize)
                    .timerDigitTracking()
                    .foregroundStyle(palette.color)
                    .lineLimit(1)
            } else {
                Text("II")
                    .timerMono(metrics.timeFontSize)
                    .timerDigitTracking()
                    .foregroundStyle(palette.color)
            }
        }
    }

    private var nameLabel: some View {
        Text(timer.recipeName ?? timer.name)
            .timerSans(metrics.nameFontSize)
            .foregroundStyle(palette.color)
            .lineLimit(metrics.nameMaxLines)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
