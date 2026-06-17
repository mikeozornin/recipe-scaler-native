//
//  TimerWidget.swift
//  HomeWidgetExtension
//
//  Spec 030 — TimerWidget: shows active cooking timers on Home Screen and Lock Screen.
//

import SwiftUI
import WidgetKit
import RecipeScalerCore

/// Home Screen + Lock Screen widget showing active cooking timers.
///
/// Spec 030 — uses `TimerSnapshotStore` (App Group) as read-only data source.
/// Live countdown via compact `Nm` / `Ns` labels and timeline reloads.
struct TimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TimerWidgetKind.id, provider: TimerWidgetProvider()) { entry in
            TimerWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("widgets.timer.name")
        .description("widgets.timer.description")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

/// Root view dispatches by `@Environment(\.widgetFamily)`.
struct TimerWidgetView: View {
    let entry: TimerWidgetEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                TimerHomeSmallView(entry: entry)
            case .accessoryCircular:
                TimerAccessoryCircularView(entry: entry)
            case .accessoryRectangular:
                TimerAccessoryRectangularView(entry: entry)
            case .accessoryInline:
                TimerAccessoryInlineView(entry: entry)
            default:
                TimerHomeSmallView(entry: entry)
            }
        }
        .timerWidgetContainerBackground(family: family, renderingMode: renderingMode)
    }
}

// MARK: - Placeholder for widget gallery

#Preview(as: .systemSmall) {
    TimerWidget()
} timeline: {
    TimerWidgetEntry.placeholderSmall()
}
