import SwiftUI

/// Servings control aligned with web `servings-control.tsx` (no separate scale slider).
struct ServingsStepperView: View {
    @Binding var servings: Int
    var accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("edit.servings")
                .appBody()
            Spacer()
            Button {
                servings = max(1, servings - 1)
            } label: {
                AppSymbol.image("minus")
                    .font(AppTypography.iconSize(AppTypography.title3Size))
            }
            .disabled(servings <= 1 || isLoading)
            .buttonStyle(.borderless)

            Text("\(servings)")
                .font(AppTypography.title3)
                .foregroundStyle(accentColor)
                .frame(minWidth: 32)

            Button {
                servings = min(99, servings + 1)
            } label: {
                AppSymbol.image("plus")
                    .font(AppTypography.iconSize(AppTypography.title3Size))
            }
            .disabled(servings >= 99 || isLoading)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
    }
}