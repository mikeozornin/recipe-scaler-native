//
//  WidgetTimerPalette.swift
//  HomeWidgetExtension
//
//  Spec 030 — rendering palette: full-color Home Screen vs monochrome accessory.
//

import SwiftUI
import WidgetKit

struct WidgetTimerPalette {
    let accent: WidgetTimerAccent
    let widgetRenderingMode: WidgetRenderingMode
    let widgetFamily: WidgetFamily

    init(
        accent: WidgetTimerAccent,
        widgetRenderingMode: WidgetRenderingMode,
        widgetFamily: WidgetFamily
    ) {
        self.accent = accent
        self.widgetRenderingMode = widgetRenderingMode
        self.widgetFamily = widgetFamily
    }

    /// Accessory families and non-`fullColor` rendering modes use a single primary tint.
    var isMonochrome: Bool {
        switch widgetFamily {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            switch widgetRenderingMode {
            case .fullColor:
                return false
            case .vibrant, .accented:
                return true
            default:
                return true
            }
        }
    }

    /// Unified timer foreground. Monochrome forces `Color.primary` (no orange/red accents).
    var timerColor: Color {
        isMonochrome ? .primary : accent.color
    }

    /// Figma ring track — hidden in monochrome (vibrancy supplies contrast).
    var showsRingTrack: Bool { !isMonochrome }

    /// Figma linear track — hidden in monochrome.
    var showsLinearTrack: Bool { !isMonochrome }

    static let trackOpacity: Double = 0.24
}

extension View {
    /// Lock Screen / vibrant rendering: let the system tint timer chrome.
    @ViewBuilder
    func widgetTimerAccentable(when palette: WidgetTimerPalette) -> some View {
        if palette.isMonochrome {
            widgetAccentable()
        } else {
            self
        }
    }
}
