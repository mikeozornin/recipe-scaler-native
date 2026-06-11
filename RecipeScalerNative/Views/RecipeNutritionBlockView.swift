import SwiftUI

/// Recipe-level KBJU block (web `nutrition-section.tsx` + `nutrition-block.tsx`).
struct RecipeNutritionBlockView: View {
    let recipe: RecipeData
    let baseServings: Int
    let scaleFactor: Double
    let accentColor: Color
    let isOnline: Bool
    let onRecalculate: (() async -> Void)?
    @Binding var viewMode: IngredientNutritionViewMode

    @State private var isCalculating = false

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
                if recipe.nutrition?.nutritionOutdated == true {
                    outdatedBanner
                }
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
            NutritionModeSegment(mode: .dish, titleKey: "nutrition.per-dish")
        ]
        if (totalWeight ?? 0) > 0 {
            segments.append(NutritionModeSegment(mode: .per100g, titleKey: "nutrition.per-100g"))
        }
        if recipe.servings > 0 {
            segments.append(NutritionModeSegment(mode: .perServing, titleKey: "nutrition.per-serving"))
        }
        segments.append(
            NutritionModeSegment(
                mode: .scaled,
                verbatimTitle: RecipeNutritionDisplay.formatScaleFactorLabel(scaleFactor),
                unselectedTitleColor: accentColor
            )
        )
        return segments
    }

    @ViewBuilder
    private var modeHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("nutrition.label-prefix")
                .appHeadline()

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
                labelKey: "nutrition.kcal",
                valueColor: valueColor
            )
            macroColumn(
                value: RecipeNutritionDisplay.formatMacroValue(macros.protein),
                labelKey: "nutrition.protein",
                valueColor: valueColor
            )
            macroColumn(
                value: RecipeNutritionDisplay.formatMacroValue(macros.fat),
                labelKey: "nutrition.fat",
                valueColor: valueColor
            )
            macroColumn(
                value: RecipeNutritionDisplay.formatMacroValue(macros.carbs),
                labelKey: "nutrition.carbs",
                valueColor: valueColor
            )
            Spacer(minLength: 0)
        }
    }

    private var outdatedBanner: some View {
        HStack(spacing: 8) {
            Text("nutrition.may-be-outdated")
                .appFootnote()
            if isOnline, let onRecalculate {
                Button {
                    guard !isCalculating else { return }
                    Task {
                        isCalculating = true
                        await onRecalculate()
                        isCalculating = false
                    }
                } label: {
                    if isCalculating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "repeat")
                            .font(AppTypography.footnote)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("nutrition.recalculate")
            }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func macroColumn(value: String, labelKey: LocalizedStringKey, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: RecipeNutritionDisplay.Typography.macroLabelTopSpacing) {
            Text(value)
                .font(RecipeNutritionDisplay.Typography.macroValueFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(labelKey)
                .appFootnote()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

private struct NutritionModeSegment: Identifiable {
    let mode: IngredientNutritionViewMode
    let titleKey: String?
    let verbatimTitle: String?
    var unselectedTitleColor: Color = .primary

    var id: IngredientNutritionViewMode { mode }

    init(mode: IngredientNutritionViewMode, titleKey: String, unselectedTitleColor: Color = .primary) {
        self.mode = mode
        self.titleKey = titleKey
        self.verbatimTitle = nil
        self.unselectedTitleColor = unselectedTitleColor
    }

    init(mode: IngredientNutritionViewMode, verbatimTitle: String, unselectedTitleColor: Color = .primary) {
        self.mode = mode
        self.titleKey = nil
        self.verbatimTitle = verbatimTitle
        self.unselectedTitleColor = unselectedTitleColor
    }
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
            Group {
                if let titleKey = segment.titleKey {
                    Text(LocalizedStringKey(titleKey))
                        .appHeadline()
                } else {
                    Text(segment.verbatimTitle ?? "")
                        .appHeadline()
                }
            }
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
