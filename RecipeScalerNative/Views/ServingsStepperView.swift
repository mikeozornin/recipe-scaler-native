import SwiftUI

/// Servings control aligned with web `servings-control.tsx` (no separate scale slider).
struct ServingsStepperView: View {
    @Binding var servings: Int
    var accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(String(localized: "edit.servings"))
                .font(.custom(AppFonts.sans, size: 17))
            Spacer()
            Button {
                servings = max(1, servings - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .disabled(servings <= 1 || isLoading)
            .buttonStyle(.borderless)

            Text("\(servings)")
                .font(.custom(AppFonts.sansMedium, size: 20))
                .foregroundStyle(accentColor)
                .frame(minWidth: 32)

            Button {
                servings = min(99, servings + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .disabled(servings >= 99 || isLoading)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
    }
}