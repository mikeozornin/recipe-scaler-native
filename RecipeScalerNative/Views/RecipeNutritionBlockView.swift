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

    private var modeItems: [(title: String, mode: IngredientNutritionViewMode)] {
        var items: [(title: String, mode: IngredientNutritionViewMode)] = [
            (Bundle.currentLocalizedString("nutrition.per-dish"), .dish)
        ]
        if (totalWeight ?? 0) > 0 {
            items.append((Bundle.currentLocalizedString("nutrition.per-100g"), .per100g))
        }
        if recipe.servings > 0 {
            items.append((Bundle.currentLocalizedString("nutrition.per-serving"), .perServing))
        }
        items.append((RecipeNutritionDisplay.formatScaleFactorLabel(scaleFactor), .scaled))
        return items
    }

    private func clampViewMode() {
        let available = modeItems.map(\.mode)
        if !available.contains(viewMode) {
            viewMode = available.first ?? .dish
        }
    }

    @ViewBuilder
    private var modeHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("nutrition.label-prefix")
                .appHeadline()

            if showsModeToggle {
                NutritionModeSegmentedPicker(modes: modeItems, selection: $viewMode)
            }
        }
        .onAppear { clampViewMode() }
        .onChange(of: recipe.id) { _, _ in clampViewMode() }
        .onChange(of: recipe.servings) { _, _ in clampViewMode() }
        .onChange(of: totalWeight) { _, _ in clampViewMode() }
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
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
    }
}

/// `UISegmentedControl` с `apportionsSegmentWidthsByContent`: общий контрол растягивается
/// по доступной ширине, но ширины сегментов подстраиваются под содержимое.
private struct NutritionModeSegmentedPicker: UIViewRepresentable {
    let modes: [(title: String, mode: IngredientNutritionViewMode)]
    @Binding var selection: IngredientNutritionViewMode

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: modes.map(\.title))
        control.selectedSegmentIndex = currentSegmentIndex
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        control.accessibilityLabel = Bundle.currentLocalizedString("nutrition.view-mode")
        applyContentBasedWidths(to: control)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        syncSegments(in: control)
        applyContentBasedWidths(to: control)
        control.selectedSegmentIndex = currentSegmentIndex
    }

    /// У сегментов UISegmentedControl нет публичного API внутренних отступов.
    /// Компенсируем: явные ширины = ширина текста + компактный боковой паддинг.
    private func applyContentBasedWidths(to control: UISegmentedControl) {
        control.apportionsSegmentWidthsByContent = false
        let attributes: [NSAttributedString.Key: Any] = [.font: AppTypography.bodyUIFont]
        for (index, item) in modes.enumerated() {
            let textWidth = (item.title as NSString).size(withAttributes: attributes).width
            control.setWidth(ceil(textWidth) + Self.segmentPadding * 2, forSegmentAt: index)
        }
    }

    private static let segmentPadding: CGFloat = 8

    /// Набор режимов меняется динамически (есть вес/порции) — обновляем сегменты и
    /// выбранный индекс при каждом обновлении.
    private func syncSegments(in control: UISegmentedControl) {
        let titles = modes.map(\.title)
        guard titles.count != control.numberOfSegments
            || (0..<control.numberOfSegments).contains(where: { control.titleForSegment(at: $0) != titles[$0] })
        else { return }
        control.removeAllSegments()
        titles.forEach { control.insertSegment(withTitle: $0, at: control.numberOfSegments, animated: false) }
    }

    private var currentSegmentIndex: Int {
        modes.firstIndex(where: { $0.mode == selection }) ?? 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: NutritionModeSegmentedPicker

        init(_ parent: NutritionModeSegmentedPicker) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: UISegmentedControl) {
            guard parent.modes.indices.contains(sender.selectedSegmentIndex) else { return }
            parent.selection = parent.modes[sender.selectedSegmentIndex].mode
        }
    }
}
