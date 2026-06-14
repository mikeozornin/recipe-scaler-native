//
//  TimerLiveActivityPalette.swift
//  RecipeScalerNative
//

import SwiftUI
import WidgetKit

/// Colors for the Lock Screen Live Activity card.
///
/// ## Rendering pipeline (iOS 17+/18+)
///
/// On the Lock Screen the system renders Live Activities in `.vibrant` mode: it
/// desaturates content and applies a tint that adapts to the Lock Screen background.
/// In Focus / Do Not Disturb with Dim Lock Screen, `\.isLuminanceReduced` additionally
/// becomes `true` and the system darkens the whole card.
///
/// Two known rendering quirks motivated the previous (hard-coded-white) version of this
/// palette:
///
/// 1. The widget extension process can resolve semantic `UIColor`s through a **stale
///    light** trait collection even when the card background is dimmed to near-black by
///    Focus, so `UIColor.label` ends up black-on-black (FB15148099 and related).
/// 2. `\.colorScheme` read from the root `ActivityConfiguration` closure returns a stale
///    default; it only reports the real value when the body is built inside a separate
///    `View` struct.
///
/// ## What changed (dim/DND fix, see `dim-live-activity.md`)
///
/// Hard-coded `.white` still failed on real devices in DND/AOD because in `.vibrant`
/// rendering the system applies a desaturation + tint pass over the foreground colors:
/// passing pure `.white` bypasses the vibrant pipeline and the system can render it as
/// the same dim color as the dimmed card background — black-on-black.
///
/// Current strategy:
///
/// - In `isLuminanceReduced` (Focus/DND/AOD dim) use semantic `.primary` / `.secondary`
///   so the system vibrant+tint pipeline adapts the foreground to the dimmed background.
/// - In `.vibrant` / `.accented` rendering modes (Lock Screen tint, Home Screen tint)
///   also use semantic `.primary` / `.secondary` so `widgetAccentable()` content
///   receives the system accent tint.
/// - In plain `.fullColor` (e.g. banner / Dynamic Island expanded, where the system does
///   not tint), use explicit colors so the widget extension process does not resolve
///   semantic colors through a stale light trait collection.
///
/// Pair with `.containerBackground(.clear, for: .widget)` on the root view — required on
/// iOS 17+ for the system to supply the Lock Screen card chrome that the vibrant tint
/// adapts to.
enum TimerLiveActivityPalette {
    static let label         = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let progressTrack  = Color(uiColor: .systemFill)

    static func accentColor(for accent: TimerLiveActivityAccent) -> Color {
        switch accent {
        case .normal:   return Color(uiColor: .label)
        case .soon:     return .orange
        case .exceeded: return Color(red: 0.98, green: 0.153, blue: 0.188)
        }
    }

    /// Foreground for primary content (timer digits, timer name).
    ///
    /// - `showsWidgetContainerBackground == true` (Lock Screen presentation): the Live Activity
    ///   is rendered as if in Dark Mode regardless of the user's system appearance
    ///   (Apple docs: "the system renders Live Activities on the Lock Screen as if in Dark Mode").
    ///   The widget extension process can read `\.colorScheme` as stale `.light` in this state
    ///   (FB15148099), and DND/Focus-dim does NOT flip `\.isLuminanceReduced` or change
    ///   `\.widgetRenderingMode` away from `.fullColor`. The only reliable way to keep the
    ///   foreground legible on the dark card chrome is to use hard-coded light colors here.
    /// - `.vibrant` / `.accented` rendering modes (Home Screen tinted mode, StandBy low-light):
    ///   use semantic `.primary` so the system's accent tint pipeline can apply.
    /// - `.fullColor` + `showsWidgetContainerBackground == false` (Dynamic Island expanded /
    ///   banner): respect the live `colorScheme`, since this surface really does track the
    ///   user's appearance.
    static func labelColor(
        colorScheme: ColorScheme,
        isLuminanceReduced: Bool,
        widgetRenderingMode: WidgetRenderingMode = .fullColor,
        showsWidgetContainerBackground: Bool = true
    ) -> Color {
        if showsWidgetContainerBackground {
            // Lock Screen card: always dark chrome, hard-coded light foreground.
            return .white
        }
        if isLuminanceReduced {
            return .primary
        }
        switch widgetRenderingMode {
        case .vibrant, .accented:
            return .primary
        default:
            return colorScheme == .dark ? .white : Color(uiColor: .label)
        }
    }

    /// Foreground for secondary content (recipe name row).
    static func secondaryLabelColor(
        colorScheme: ColorScheme,
        isLuminanceReduced: Bool,
        widgetRenderingMode: WidgetRenderingMode = .fullColor,
        showsWidgetContainerBackground: Bool = true
    ) -> Color {
        if showsWidgetContainerBackground {
            return Color(white: 0.85)
        }
        if isLuminanceReduced {
            return .secondary
        }
        switch widgetRenderingMode {
        case .vibrant, .accented:
            return .secondary
        default:
            return colorScheme == .dark ? Color(white: 0.78) : Color(uiColor: .secondaryLabel)
        }
    }

    /// Progress track fill. Slightly lighter than the background so the track
    /// stays visible on both pure-black dark and dimmed Focus backgrounds.
    static func progressTrackColor(
        colorScheme: ColorScheme,
        isLuminanceReduced: Bool,
        widgetRenderingMode: WidgetRenderingMode = .fullColor,
        showsWidgetContainerBackground: Bool = true
    ) -> Color {
        if showsWidgetContainerBackground {
            return Color.white.opacity(0.22)
        }
        if isLuminanceReduced {
            return Color(uiColor: .systemFill)
        }
        switch widgetRenderingMode {
        case .vibrant, .accented:
            return Color.primary.opacity(0.22)
        default:
            return colorScheme == .dark
                ? Color.white.opacity(0.22)
                : Color(uiColor: .systemFill)
        }
    }

    /// Accent color resolved against the live appearance. `.normal` follows the
    /// label color; the alert states (`.soon` / `.exceeded`) keep their hue but
    /// are lightened slightly when the card is dimmed for contrast.
    static func accentColor(
        for accent: TimerLiveActivityAccent,
        colorScheme: ColorScheme,
        isLuminanceReduced: Bool,
        widgetRenderingMode: WidgetRenderingMode = .fullColor,
        showsWidgetContainerBackground: Bool = true
    ) -> Color {
        switch accent {
        case .normal:
            return labelColor(
                colorScheme: colorScheme,
                isLuminanceReduced: isLuminanceReduced,
                widgetRenderingMode: widgetRenderingMode,
                showsWidgetContainerBackground: showsWidgetContainerBackground
            )
        case .soon:
            switch widgetRenderingMode {
            case .vibrant, .accented:
                return .orange
            default:
                return isLuminanceReduced
                    ? Color(red: 1.0, green: 0.71, blue: 0.34)
                    : .orange
            }
        case .exceeded:
            return Color(red: 0.98, green: 0.153, blue: 0.188)
        }
    }
}
