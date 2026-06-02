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

    var body: some View {
        NavigationStack {
            ScrollView {
                StepsSection(
                    htmlContent: RecipeDescriptionFixture.allElementsHTML,
                    accentColor: accent
                )
                .padding(.vertical, 16)
            }
            .navigationTitle("Description fixture")
            .accessibilityIdentifier("description-fixture-preview")
        }
    }
}
#endif