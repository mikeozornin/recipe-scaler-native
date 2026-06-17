//
//  WidgetTimerRing.swift
//  HomeWidgetExtension
//
//  Spec 030 — ring: full track + progress arc on the same 56pt circle (center stroke).
//

import SwiftUI
import RecipeScalerCore

struct WidgetTimerRing: View {
    let timer: TimerSnapshot
    let now: Date
    let palette: WidgetTimerPalette
    let digitSize: CGFloat

    private var ringDiameter: CGFloat { WidgetTimerLayout.ringTrackSize }

    var body: some View {
        ZStack {
            if palette.showsRingTrack {
                Circle()
                    .stroke(
                        palette.timerColor.opacity(WidgetTimerPalette.trackOpacity),
                        lineWidth: WidgetTimerLayout.ringStrokeWidth
                    )
                    .frame(width: ringDiameter, height: ringDiameter)
            }

            Circle()
                .trim(from: 0, to: timer.progressFraction(now: now))
                .stroke(
                    palette.timerColor,
                    style: StrokeStyle(
                        lineWidth: WidgetTimerLayout.ringStrokeWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .frame(width: ringDiameter, height: ringDiameter)

            countdown
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .widgetTimerAccentable(when: palette)
    }

    @ViewBuilder
    private func ringCountdownText<Content: View>(_ content: Content) -> some View {
        content
            .frame(height: WidgetTimerLayout.ringDigitLineHeight)
    }

    @ViewBuilder
    private var countdown: some View {
        switch timer.phase {
        case .running, .exceeded:
            let remaining = timer.remainingSeconds(now: now)
            ringCountdownText(
                Text(WidgetTimerFormatting.compactRemaining(seconds: remaining))
                    .widgetMono(digitSize)
                    .widgetTimerTracking()
                    .foregroundStyle(palette.timerColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            )

        case .paused:
            if let remaining = timer.pausedRemainingSeconds {
                ringCountdownText(
                    Text(WidgetTimerFormatting.shortClock(remaining))
                        .widgetMono(digitSize)
                        .widgetTimerTracking()
                        .foregroundStyle(palette.timerColor)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                )
            } else {
                ringCountdownText(
                    Text("II")
                        .widgetMono(digitSize)
                        .widgetTimerTracking()
                        .foregroundStyle(palette.timerColor)
                )
            }
        }
    }
}
