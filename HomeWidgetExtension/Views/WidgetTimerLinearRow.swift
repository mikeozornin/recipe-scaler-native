//
//  WidgetTimerLinearRow.swift
//  HomeWidgetExtension
//
//  Spec 030 — 2-timer row: bar 89pt left, time overlay, label full 137pt (under time).
//

import SwiftUI
import RecipeScalerCore

struct WidgetTimerLinearRow: View {
    let timer: TimerSnapshot
    let now: Date
    let palette: WidgetTimerPalette

    private var labelTopInset: CGFloat {
        WidgetTimerLayout.linearBarHeight + WidgetTimerLayout.linearRowSpacing
    }

    var body: some View {
        Color.clear
            .frame(
                width: WidgetTimerLayout.contentSize,
                height: WidgetTimerLayout.twoTimerRowHeight
            )
            .overlay(alignment: .topLeading) {
                linearBar
            }
            .overlay(alignment: .topLeading) {
                recipeNameLabel
                    .padding(.top, labelTopInset)
            }
            .overlay(alignment: .topTrailing) {
                countdownTime
                    .frame(width: WidgetTimerLayout.linearTimeWidth, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: WidgetTimerLayout.linearTimeOffsetY)
            }
            .widgetTimerAccentable(when: palette)
    }

    /// Same layout contract as `singleTimerState` — `fixedSize` before fixed frame enables wrap.
    private var recipeNameLabel: some View {
        WidgetFonts.recipeNameText(timer.recipeName ?? timer.name)
            .foregroundStyle(palette.timerColor)
            .lineLimit(WidgetTimerLayout.linearNameMaxLines)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                width: WidgetTimerLayout.contentSize,
                height: WidgetTimerLayout.twoTimerLabelHeight,
                alignment: .topLeading
            )
    }

    private var linearBar: some View {
        let trackWidth = WidgetTimerLayout.linearBarMaxWidth
        let progress = timer.progressFraction(now: now)

        return ZStack(alignment: .leading) {
            if palette.showsLinearTrack {
                Rectangle()
                    .fill(palette.timerColor.opacity(WidgetTimerPalette.trackOpacity))
                    .frame(
                        width: trackWidth,
                        height: WidgetTimerLayout.linearTrackHeight
                    )
            }

            Rectangle()
                .fill(palette.timerColor)
                .frame(
                    width: trackWidth * progress,
                    height: WidgetTimerLayout.linearFillHeight
                )
        }
        .frame(
            width: trackWidth,
            height: WidgetTimerLayout.linearBarHeight,
            alignment: .leading
        )
    }

    @ViewBuilder
    private var countdownTime: some View {
        switch timer.phase {
        case .running, .exceeded:
            Text(WidgetTimerFormatting.compactRemaining(seconds: timer.remainingSeconds(now: now)))
                .widgetMono(WidgetTimerLayout.linearTimeSize)
                .widgetTimerTracking()
                .foregroundStyle(palette.timerColor)
                .lineLimit(1)

        case .paused:
            if let remaining = timer.pausedRemainingSeconds {
                Text(WidgetTimerFormatting.shortClock(remaining))
                    .widgetMono(WidgetTimerLayout.linearTimeSize)
                    .widgetTimerTracking()
                    .foregroundStyle(palette.timerColor)
                    .lineLimit(1)
            } else {
                Text("II")
                    .widgetMono(WidgetTimerLayout.linearTimeSize)
                    .widgetTimerTracking()
                    .foregroundStyle(palette.timerColor)
            }
        }
    }
}
