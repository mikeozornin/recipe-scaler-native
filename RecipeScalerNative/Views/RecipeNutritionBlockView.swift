import SwiftUI

/// Recipe-level KBJU block (web `nutrition-section.tsx` + `nutrition-block.tsx`).
struct RecipeNutritionBlockView: View {
    let recipe: RecipeData
    let baseServings: Int
    let scaleFactor: Double
    let accentColor: Color
    @Binding var viewMode: IngredientNutritionViewMode

    private var totalWeight: Double? {
        RecipeNutritionDisplay.effectiveTotalWeight(from: recipe)
    }

    private var showsModeToggle: Bool {
        let hasWeight = (totalWeight ?? 0) > 0
        let hasServings = recipe.servings > 0
        return hasWeight || hasServings
    }

    private var scaledServings: Int {
        max(1, Int((Double(max(1, baseServings)) * scaleFactor).rounded()))
    }

    private var displayedMacros: RecipeNutritionDisplay.Macros? {
        guard let effective = RecipeNutritionDisplay.effectiveMacros(from: recipe) else { return nil }
        return RecipeNutritionDisplay.displayMacros(
            effective: effective,
            baseServings: baseServings,
            viewServings: scaledServings,
            recipeServings: max(1, recipe.servings),
            totalWeight: totalWeight,
            mode: viewMode
        )
    }

    var body: some View {
        if let macros = displayedMacros {
            VStack(alignment: .leading, spacing: 8) {
                modeHeader
                macrosRow(macros)
                    .id(viewMode)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .onChange(of: viewMode) { _, mode in
                NutritionViewModeStorage.save(mode)
            }
        }
    }

    private var modeSegments: [NutritionModeSegment] {
        var segments: [NutritionModeSegment] = [
            NutritionModeSegment(mode: .dish, title: String(localized: "nutrition.per-dish"))
        ]
        if (totalWeight ?? 0) > 0 {
            segments.append(NutritionModeSegment(mode: .per100g, title: String(localized: "nutrition.per-100g")))
        }
        if recipe.servings > 0 {
            segments.append(NutritionModeSegment(mode: .perServing, title: String(localized: "nutrition.per-serving")))
        }
        segments.append(
            NutritionModeSegment(
                mode: .scaled,
                title: RecipeNutritionDisplay.formatScaleFactorLabel(scaleFactor),
                unselectedTitleColor: accentColor
            )
        )
        return segments
    }

    @ViewBuilder
    private var modeHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(String(localized: "nutrition.label-prefix"))
                .font(AppTypography.bodySemibold)

            if showsModeToggle {
                NutritionModeSegmentedControl(
                    segments: modeSegments,
                    selection: $viewMode
                )
            }
        }
        .onAppear { clampViewMode() }
        .onChange(of: recipe.id) { _, _ in clampViewMode() }
        .onChange(of: recipe.servings) { _, _ in clampViewMode() }
        .onChange(of: totalWeight) { _, _ in clampViewMode() }
    }

    private func clampViewMode() {
        let available = Set(modeSegments.map(\.mode))
        if !available.contains(viewMode) {
            viewMode = modeSegments.first?.mode ?? .dish
        }
    }

    private func macrosRow(_ macros: RecipeNutritionDisplay.Macros) -> some View {
        let valueColor: Color = viewMode == .scaled ? accentColor : .primary
        return HStack(alignment: .bottom, spacing: RecipeNutritionDisplay.Typography.macroColumnSpacing) {
            macroColumn(
                value: RecipeNutritionDisplay.formatCalories(macros.calories),
                label: String(localized: "nutrition.kcal"),
                valueColor: valueColor
            )
            macroColumn(
                value: RecipeNutritionDisplay.formatMacroValue(macros.protein),
                label: String(localized: "nutrition.protein"),
                valueColor: valueColor
            )
            macroColumn(
                value: RecipeNutritionDisplay.formatMacroValue(macros.fat),
                label: String(localized: "nutrition.fat"),
                valueColor: valueColor
            )
            macroColumn(
                value: RecipeNutritionDisplay.formatMacroValue(macros.carbs),
                label: String(localized: "nutrition.carbs"),
                valueColor: valueColor
            )
            Spacer(minLength: 0)
        }
    }

    private func macroColumn(value: String, label: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: RecipeNutritionDisplay.Typography.macroLabelTopSpacing) {
            Text(value)
                .font(RecipeNutritionDisplay.Typography.macroValueFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(RecipeNutritionDisplay.Typography.macroLabelFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

private struct NutritionModeSegment: Identifiable {
    let mode: IngredientNutritionViewMode
    let title: String
    var unselectedTitleColor: Color = .primary

    var id: IngredientNutritionViewMode { mode }
}

/// Glued segmented control (web `ToggleGroup` with `gap-0` / shared outer border).
private struct NutritionModeSegmentedControl: View {
    let segments: [NutritionModeSegment]
    @Binding var selection: IngredientNutritionViewMode

    private let trackInset: CGFloat = 2
    private let cornerRadius: CGFloat = 8
    private let segmentCornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                segmentButton(segment: segment, index: index)
            }
        }
        .padding(trackInset)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segmentButton(segment: NutritionModeSegment, index: Int) -> some View {
        let isSelected = selection == segment.mode
        return Button {
            selection = segment.mode
        } label: {
            Text(segment.title)
                .font(AppTypography.sansMedium(AppTypography.calloutSize))
                .foregroundStyle(isSelected ? Color.primary : segment.unselectedTitleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: segmentCornerRadius, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 1 : 0)
    }
}