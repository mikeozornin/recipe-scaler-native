import SwiftUI

private enum NutritionFieldFocus: Hashable {
    case calories, protein, fat, carbs
}

/// Per-ingredient nutrition editor (web `EditIngredientNutrition`, values per 100 g).
struct EditIngredientNutritionSheet: View {
    let ingredient: IngredientData
    let onSave: (Double, Double, Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var calories: String
    @State private var protein: String
    @State private var fat: String
    @State private var carbs: String
    @FocusState private var focusedField: NutritionFieldFocus?

    private let fieldOrder: [NutritionFieldFocus] = [.calories, .protein, .fat, .carbs]

    init(
        ingredient: IngredientData,
        onSave: @escaping (Double, Double, Double, Double) -> Void
    ) {
        self.ingredient = ingredient
        self.onSave = onSave
        let per100g = IngredientNutritionEditing.per100gValues(from: ingredient)
        _calories = State(initialValue: Self.formatCalories(per100g.calories))
        _protein = State(initialValue: Self.formatMacro(per100g.protein))
        _fat = State(initialValue: Self.formatMacro(per100g.fat))
        _carbs = State(initialValue: Self.formatMacro(per100g.carbs))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: ingredient.name)
                        .appBody()
                        .foregroundStyle(Color(.label))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("nutrition.per-100g-note")
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Form {
                    Section {
                        nutritionRow("nutrition.kcal", text: $calories, focus: .calories)
                        nutritionRow("nutrition.protein.label", text: $protein, focus: .protein)
                        nutritionRow("nutrition.fat.label", text: $fat, focus: .fat)
                        nutritionRow("nutrition.carbs.label", text: $carbs, focus: .carbs)
                    }
                }
                .appListBodyTypography()
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle("nutrition.ingredient.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("edit.cancel") { dismiss() }
                        .appToolbarTextButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("edit.done") { saveAndDismiss() }
                        .appToolbarConfirmButton()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button { focusPrevious() } label: {
                        AppToolbarStyle.icon("chevron.up")
                    }
                    .appToolbarIconButton()
                    .disabled(!canFocusPrevious)

                    Color.clear.frame(width: 8)

                    Button { focusNext() } label: {
                        AppToolbarStyle.icon("chevron.down")
                    }
                    .appToolbarIconButton()
                    .disabled(!canFocusNext)

                    Spacer()

                    Button("edit.done") { focusedField = nil }
                        .appToolbarTextButton()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var canFocusPrevious: Bool {
        guard let focusedField, let index = fieldOrder.firstIndex(of: focusedField) else { return false }
        return index > 0
    }

    private var canFocusNext: Bool {
        guard let focusedField, let index = fieldOrder.firstIndex(of: focusedField) else { return false }
        return index < fieldOrder.count - 1
    }

    private func focusPrevious() {
        guard let focusedField, let index = fieldOrder.firstIndex(of: focusedField), index > 0 else { return }
        self.focusedField = fieldOrder[index - 1]
    }

    private func focusNext() {
        guard let focusedField, let index = fieldOrder.firstIndex(of: focusedField), index < fieldOrder.count - 1 else { return }
        self.focusedField = fieldOrder[index + 1]
    }

    private func saveAndDismiss() {
        focusedField = nil
        let per100g = IngredientNutritionEditing.Per100gValues(
            calories: Self.parse(calories) ?? 0,
            protein: Self.parse(protein) ?? 0,
            fat: Self.parse(fat) ?? 0,
            carbs: Self.parse(carbs) ?? 0
        )
        let absolute = IngredientNutritionEditing.absoluteValues(
            per100g: per100g,
            weightGrams: ingredient.resolvedWeightGrams
        )
        onSave(absolute.calories, absolute.protein, absolute.fat, absolute.carbs)
    }

    private func nutritionRow(_ labelKey: LocalizedStringKey, text: Binding<String>, focus: NutritionFieldFocus) -> some View {
        LabeledContent(labelKey) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(AppTypography.mono(AppTypography.bodySize))
                .focused($focusedField, equals: focus)
        }
    }

    private static func formatCalories(_ value: Double) -> String {
        guard value != 0 else { return "" }
        return String(Int(value.rounded()))
    }

    private static func formatMacro(_ value: Double) -> String {
        guard value != 0 else { return "" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}
