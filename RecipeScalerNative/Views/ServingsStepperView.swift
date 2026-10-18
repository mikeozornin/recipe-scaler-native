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
                .font(AppTypography.sans(AppTypography.title3Size))
            Spacer()
            // −, number and + share one pale accent capsule; the label above already says «Servings».
            HStack(spacing: 0) {
                stepButton("minus", disabled: currentServings <= 1 || isLoading, action: onDecrement)

                Text(RecipeServings.formatDisplay(currentServings))
                    .font(AppTypography.sansMedium(18))
                    .monospacedDigit()
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .scalingNumberTransition(value: currentServings)
                    .frame(minWidth: 34)
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailServingsValue)

                stepButton("plus", disabled: currentServings >= 99 || isLoading, action: onIncrement)
            }
            .frame(height: 36)
            .background(Capsule().fill(accentColor.opacity(0.13)))
        }
        .frame(minHeight: 48)
        .padding(.horizontal)
    }

    private func stepButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AppSymbol.image(symbol)
                .font(AppTypography.iconSize(AppTypography.title3Size))
                .foregroundStyle(accentColor)
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}

extension View {
    /// Digits roll up or down when `value` changes, so a servings step visibly lands on
    /// the numbers it rescales. A plain cross-fade under Reduce Motion.
    func scalingNumberTransition(value: Double) -> some View {
        modifier(ScalingNumberTransition(value: value))
    }
}

private struct ScalingNumberTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText(value: value))
            .animation(AppMotion.enter, value: value)
    }
}
