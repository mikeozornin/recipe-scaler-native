//
//  AssistantFabStyle.swift
//  RecipeScalerNative
//

import SwiftUI

enum AssistantFabStyle {
    static let margin: CGFloat = 16
    static let iconPadding: CGFloat = 14
    static let diameter: CGFloat = AppTypography.title2Size + iconPadding * 2

    @ViewBuilder
    static var iconLabel: some View {
        AppSymbol.image("sparkles")
            .font(AppTypography.iconSize(AppTypography.title2Size))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AssistantFabLegacyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background {
                Circle()
                    .fill(Color.accentColor)
                    .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
                    .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 12)
            }
            .frame(width: AssistantFabStyle.diameter, height: AssistantFabStyle.diameter)
    }
}

struct AssistantFabButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                AssistantFabStyle.iconLabel
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .frame(width: AssistantFabStyle.diameter, height: AssistantFabStyle.diameter)
        } else {
            Button(action: action) {
                AssistantFabStyle.iconLabel
            }
            .buttonStyle(AssistantFabLegacyButtonStyle())
        }
    }
}
