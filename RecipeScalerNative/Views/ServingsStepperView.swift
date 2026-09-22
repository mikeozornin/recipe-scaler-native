import SwiftUI

/// Servings control aligned with web `servings-control.tsx` (no separate scale slider).
/// Display can be fractional (after ingredient-driven scale); ± buttons step whole servings.
struct ServingsStepperView: View {
    /// Continuous current servings (base × scaleFactor), web `getCurrentServings`.
    let currentServings: Double
    var accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    var isLoading: Bool = false
    var onDecrement: () -> Void
    var onIncrement: () -> Void

    /// Legacy Int binding bridge — prefer continuous `currentServings` initializer.
    init(
        servings: Binding<Int>,
        accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)"),
        isLoading: Bool = false
    ) {
        self.currentServings = Double(servings.wrappedValue)
        self.accentColor = accentColor
        self.isLoading = isLoading
        self.onDecrement = { servings.wrappedValue = max(1, servings.wrappedValue - 1) }
        self.onIncrement = { servings.wrappedValue = min(99, servings.wrappedValue + 1) }
    }

    init(
        currentServings: Double,
        accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)"),
        isLoading: Bool = false,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) {
        self.currentServings = currentServings
        self.accentColor = accentColor
        self.isLoading = isLoading
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("edit.servings")
                .appBody()
            Spacer()
            Button(action: onDecrement) {
                AppSymbol.image("minus")
                    .font(AppTypography.iconSize(AppTypography.title3Size))
            }
            .disabled(currentServings <= 1 || isLoading)
            .buttonStyle(.borderless)

            Text(RecipeServings.formatDisplay(currentServings))
                .appHeadline()
                .foregroundStyle(accentColor)
                .frame(minWidth: 32)

            Button(action: onIncrement) {
                AppSymbol.image("plus")
                    .font(AppTypography.iconSize(AppTypography.title3Size))
            }
            .disabled(currentServings >= 99 || isLoading)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
    }
}
