import RecipeScalerCore
import SwiftUI

struct IngredientIllustrationThumb: View {
    let illustrationId: String?
    var isInteractive: Bool = false
    var onTap: (() -> Void)?

    private var resolvedId: String? {
        guard let raw = illustrationId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              IngredientIllustrationCatalog.shared.contains(id: raw)
        else { return nil }
        return raw
    }

    var body: some View {
        Group {
            if isInteractive, let onTap {
                Button(action: onTap) {
                    thumbContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("recipes.ingredient-icon.choose"))
                .accessibilityIdentifier(AccessibilityIdentifiers.ingredientIcon)
            } else {
                thumbContent
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var thumbContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: IngredientIllustrationLayoutMetrics.cornerRadiusPt, style: .continuous)
                .fill(Color.white)
            if let resolvedId, let uiImage = IngredientIllustrationImageStore.uiImage(for: resolvedId) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                IngredientBowlIcon(size: 22)
            }
        }
        .frame(
            width: IngredientIllustrationLayoutMetrics.displaySlotPt,
            height: IngredientIllustrationLayoutMetrics.displaySlotPt
        )
        .clipShape(RoundedRectangle(cornerRadius: IngredientIllustrationLayoutMetrics.cornerRadiusPt, style: .continuous))
    }
}

/// Fixed-width leading slot: thumb, empty spacer (headers), or optional «+» label.
struct IngredientIllustrationSlot: View {
    enum Content {
        case thumb(illustrationId: String?, isInteractive: Bool, onTap: (() -> Void)?)
        case empty
        case plusLabel
    }

    let content: Content

    var body: some View {
        Group {
            switch content {
            case .thumb(let id, let interactive, let onTap):
                IngredientIllustrationThumb(illustrationId: id, isInteractive: interactive, onTap: onTap)
                    /// Recipe list preview sits in row overlay (full 44 pt); cancel row chrome top inset.
                    .padding(.top, -RecipeRowLayoutMetrics.ingredientRowVerticalPadding)
            case .empty:
                Color.clear
            case .plusLabel:
                Text("+")
                    .appBody()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: RecipeRowLayoutMetrics.illustrationSlotWidth,
            height: RecipeRowLayoutMetrics.ingredientBodyLineHeight,
            alignment: .topLeading
        )
    }
}