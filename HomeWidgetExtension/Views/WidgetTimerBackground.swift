//
//  WidgetTimerBackground.swift
//  HomeWidgetExtension
//
//  Spec 030 — widget chrome: Home Screen fill vs accessory (clear).
//

import SwiftUI
import WidgetKit

enum WidgetTimerBackground {
  /// Figma `backgrounds/secondary` — semantic `secondarySystemBackground`.
  static let homeScreen = Color(.secondarySystemBackground)

  @ViewBuilder
  static func container(for family: WidgetFamily, renderingMode: WidgetRenderingMode) -> some View {
    switch family {
    case .systemSmall:
      if renderingMode == .fullColor {
        ContainerRelativeShape()
          .fill(homeScreen)
      } else {
        Color.clear
      }
    default:
      Color.clear
    }
  }
}

extension View {
  /// Applies spec-correct `containerBackground` for the active widget family.
  func timerWidgetContainerBackground(
    family: WidgetFamily,
    renderingMode: WidgetRenderingMode
  ) -> some View {
    containerBackground(for: .widget) {
      WidgetTimerBackground.container(for: family, renderingMode: renderingMode)
    }
  }
}
