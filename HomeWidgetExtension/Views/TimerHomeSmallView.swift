//
//  TimerHomeSmallView.swift
//  HomeWidgetExtension
//
//  Spec 030 — Home Screen `systemSmall` (169×169).
//  Figma `107:207` / `107:266`: padding 16, grid gap 12, ring 56pt path (≈62pt outer).
//

import SwiftUI
import WidgetKit
import RecipeScalerCore

struct TimerHomeSmallView: View {
    let entry: TimerWidgetEntry

    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.widgetFamily) private var widgetFamily

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: WidgetTimerLayout.gridGap),
            GridItem(.flexible(), spacing: WidgetTimerLayout.gridGap),
        ]
    }

    var body: some View {
        Group {
            switch entry.timers.count {
            case 0:
                emptyState
            case 1:
                singleTimerState(entry.timers[0])
            case 2:
                twoTimersState
            default:
                multiRingGridState
            }
        }
        .padding(WidgetTimerLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "\(DeepLinkURL.baseScheme)://home"))
    }

    // MARK: - Empty (Figma 107:303)

    private var emptyState: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color(.label))
                Text("widgets.timer.empty")
                    .widgetSans(15)
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: geometry.size.width)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - 1 timer (Figma 107:238)

    private func singleTimerState(_ timer: TimerSnapshot) -> some View {
        let palette = palette(for: timer)
        return VStack(alignment: .leading, spacing: WidgetTimerLayout.gridGap) {
            HStack(alignment: .top, spacing: 0) {
                WidgetTimerRing(
                    timer: timer,
                    now: entry.date,
                    palette: palette,
                    digitSize: WidgetTimerLayout.ringDigitSizeSingle
                )
                Spacer(minLength: 0)
            }
            .frame(height: WidgetTimerLayout.ringTrackSize, alignment: .topLeading)

            WidgetFonts.recipeNameText(timer.recipeName ?? timer.name)
                .foregroundStyle(palette.timerColor)
                .lineLimit(WidgetTimerLayout.linearNameMaxLines)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    width: WidgetTimerLayout.contentSize,
                    height: WidgetTimerLayout.singleTimerLabelBlockHeight,
                    alignment: .topLeading
                )
        }
        .frame(
            width: WidgetTimerLayout.contentSize,
            height: WidgetTimerLayout.contentSize,
            alignment: .topLeading
        )
    }

    // MARK: - 2 timers (Figma 107:318)

    private var twoTimersState: some View {
        VStack(alignment: .leading, spacing: WidgetTimerLayout.gridGap) {
            ForEach(Array(entry.timers.prefix(2))) { timer in
                WidgetTimerLinearRow(
                    timer: timer,
                    now: entry.date,
                    palette: palette(for: timer)
                )
            }
        }
        .frame(
            width: WidgetTimerLayout.contentSize,
            height: WidgetTimerLayout.contentSize,
            alignment: .topLeading
        )
    }

    // MARK: - 3–4 timers (Figma 107:208 / 107:221)

    private var multiRingGridState: some View {
        LazyVGrid(columns: columns, spacing: WidgetTimerLayout.gridGap) {
            ForEach(Array(entry.timers.prefix(4))) { timer in
                WidgetTimerRing(
                    timer: timer,
                    now: entry.date,
                    palette: palette(for: timer),
                    digitSize: WidgetTimerLayout.ringDigitSizeMulti
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: WidgetTimerLayout.ringTrackSize,
                    alignment: .topLeading
                )
            }
        }
    }

    private func palette(for timer: TimerSnapshot) -> WidgetTimerPalette {
        WidgetTimerPalette(
            accent: WidgetTimerAccent.resolve(
                phase: timer.phase,
                remainingSeconds: timer.remainingSeconds(now: entry.date),
                totalDuration: timer.totalDurationSeconds
            ),
            widgetRenderingMode: widgetRenderingMode,
            widgetFamily: widgetFamily
        )
    }
}

// MARK: - Canvas previews (Figma 107:207 / 107:266 / 107:332)

private enum TimerHomeSmallPreview {
    static let widgetSize: CGFloat = 169

    static func canvas(_ entry: TimerWidgetEntry, monochrome: Bool = false) -> some View {
        TimerHomeSmallView(entry: entry)
            .frame(width: widgetSize, height: widgetSize)
            .background(monochrome ? Color.clear : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    static func mono(_ entry: TimerWidgetEntry) -> some View {
        canvas(entry, monochrome: true)
            .environment(\.widgetRenderingMode, .vibrant)
            .colorScheme(.dark)
    }
}

#Preview("0 timers — light") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.empty)
        .colorScheme(.light)
}

#Preview("1 timer — light") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.placeholderOne())
        .colorScheme(.light)
}

#Preview("2 timers — light") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.placeholderTwo())
        .colorScheme(.light)
}

#Preview("3 timers — light") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.placeholderThree())
        .colorScheme(.light)
}

#Preview("4 timers — light") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.placeholderFour())
        .colorScheme(.light)
}

#Preview("0 timers — dark") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.empty)
        .colorScheme(.dark)
}

#Preview("1 timer — dark") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.placeholderOne())
        .colorScheme(.dark)
}

#Preview("2 timers — dark") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.placeholderTwo())
        .colorScheme(.dark)
}

#Preview("3 timers — dark") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.placeholderThree())
        .colorScheme(.dark)
}

#Preview("4 timers — dark") {
    TimerHomeSmallPreview.canvas(TimerWidgetEntry.placeholderFour())
        .colorScheme(.dark)
}

#Preview("1 timer — mono vibrant") {
    TimerHomeSmallPreview.mono(TimerWidgetEntry.placeholderOne())
}

#Preview("2 timers — mono vibrant") {
    TimerHomeSmallPreview.mono(TimerWidgetEntry.placeholderTwo())
}

#Preview("3 timers — mono vibrant") {
    TimerHomeSmallPreview.mono(TimerWidgetEntry.placeholderThree())
}

#Preview("4 timers — mono vibrant") {
    TimerHomeSmallPreview.mono(TimerWidgetEntry.placeholderFour())
}

#Preview("0 timers — mono vibrant") {
    TimerHomeSmallPreview.mono(TimerWidgetEntry.empty)
}
