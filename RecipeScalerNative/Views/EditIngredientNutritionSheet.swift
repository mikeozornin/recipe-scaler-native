import SwiftUI

private enum NutritionFieldFocus: Hashable {
    case calories, protein, fat, carbs
}

/// Per-ingredient nutrition editor (web `EditIngredientNutrition`).
struct EditIngredientNutritionSheet: View {
    let ingredientName: String
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
        self.ingredientName = ingredient.name
        self.onSave = onSave
        _calories = State(initialValue: Self.format(ingredient.calories))
        _protein = State(initialValue: Self.format(ingredient.protein))
        _fat = State(initialValue: Self.format(ingredient.fat))
        _carbs = State(initialValue: Self.format(ingredient.carbs))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(ingredientName)
                    .font(.custom(AppFonts.sansMedium, size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    nutritionField(String(localized: "nutrition.kcal.short"), text: $calories, focus: .calories)
                    nutritionField(String(localized: "nutrition.protein.short"), text: $protein, focus: .protein)
                    nutritionField(String(localized: "nutrition.fat.short"), text: $fat, focus: .fat)
                    nutritionField(String(localized: "nutrition.carbs.short"), text: $carbs, focus: .carbs)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .navigationTitle(String(localized: "nutrition.ingredient.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "edit.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "edit.done")) { saveAndDismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button { focusPrevious() } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canFocusPrevious)

                    Button { focusNext() } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canFocusNext)

                    Spacer()

                    Button(String(localized: "edit.done")) { focusedField = nil }
                }
            }
        }
        .presentationDetents([.height(200)])
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
        onSave(
            Self.parse(calories) ?? 0,
            Self.parse(protein) ?? 0,
            Self.parse(fat) ?? 0,
            Self.parse(carbs) ?? 0
        )
    }

    private func nutritionField(_ label: String, text: Binding<String>, focus: NutritionFieldFocus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom(AppFonts.sans, size: 12))
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .font(.custom(AppFonts.mono, size: 16))
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($focusedField, equals: focus)
        }
        .frame(maxWidth: .infinity)
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value { return String(Int(value)) }
        return String(value)
    }

    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}