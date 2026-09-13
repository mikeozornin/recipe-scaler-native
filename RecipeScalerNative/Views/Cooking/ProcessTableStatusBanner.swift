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
                .appFootnote()
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
                            pointSize: AppTypography.footnoteSize,
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
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeProcessTableBanner)
    }
}
