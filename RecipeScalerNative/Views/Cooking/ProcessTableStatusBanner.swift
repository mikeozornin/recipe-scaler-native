import SwiftUI

struct ProcessTableStatusBanner: View {
    enum Kind {
        case outdated
        case missing
    }

    let kind: Kind
    var canRecalculate: Bool
    var isOnline: Bool
    var isRebuilding: Bool
    var onRecalculate: (() -> Void)?

    var body: some View {
        HStack(spacing: ProcessTableLayout.bannerSpacing) {
            Text(kind == .missing ? "recipe.process-table.not-built" : "recipe.process-table.may-be-outdated")
                .appBody()
                .fixedSize(horizontal: false, vertical: true)
            if canRecalculate, isOnline, let onRecalculate {
                Button(action: {
                    onRecalculate()
                }) {
                    if isRebuilding {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        AppSymbol.sizedImage(
                            "repeat",
                            pointSize: AppTypography.bodySize,
                            weight: .semibold
                        )
                    }
                }
                .buttonStyle(.plain)
                .frame(width: ProcessTableLayout.ctaMinHit, height: ProcessTableLayout.ctaMinHit)
                .contentShape(Rectangle())
                .padding(.vertical, ProcessTableLayout.bannerHitVerticalCollapse)
                .accessibilityLabel(kind == .missing ? "recipe.process-table.build" : "recipe.process-table.recalculate")
                .disabled(isRebuilding)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeProcessTableBanner)
    }
}

enum ProcessTableClassicChrome {
    static func canStartCooking(_ recipe: RecipeData?) -> Bool {
        recipe?.processTable != nil
    }

    static func showsMissingBanner(allowsRebuild: Bool, recipe: RecipeData?) -> Bool {
        allowsRebuild && recipe != nil && recipe?.processTable == nil
    }
}
