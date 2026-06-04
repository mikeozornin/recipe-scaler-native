//
//  DescriptionFixturePreviewView.swift
//  RecipeScalerNative
//
//  DEBUG: launch with `-ShowDescriptionFixture` to verify description UI in Simulator.
//

import SwiftUI

#if DEBUG
struct DescriptionFixturePreviewView: View {
    private let accent = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    @State private var timerPopover: DescriptionTimerPopoverState?

    var body: some View {
        NavigationStack {
            ScrollView {
                StepsSection(
                    htmlContent: RecipeDescriptionFixture.allElementsHTML,
                    accentColor: accent,
                    timerPopover: $timerPopover
                )
                .padding(.vertical, 16)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10).onChanged { _ in
                    if timerPopover != nil { timerPopover = nil }
                }
            )
            .overlay {
                if let popover = timerPopover {
                    DescriptionTimerPopoverOverlay(
                        state: popover,
                        accentColor: accent,
                        onStart: {},
                        onDismiss: { timerPopover = nil }
                    )
                }
            }
            .navigationTitle("Description fixture")
            .accessibilityIdentifier("description-fixture-preview")
        }
    }
}
#endif