//
//  DescriptionMarkupFlow.swift
//  RecipeScalerNative
//
//  Native sheets for timer / ingredient markup in description editor (019).
//

import SwiftUI

struct DescriptionTimerMarkupDraft: Identifiable {
    let id = UUID()
    let selectedText: String
    let value: Double
}

enum DescriptionTimerUnit: String, CaseIterable, Identifiable {
    case hours
    case minutes
    case seconds

    var id: String { rawValue }

    var localizationKey: LocalizedStringKey {
        switch self {
        case .hours: "timers.time-types.hours"
        case .minutes: "timers.time-types.minutes"
        case .seconds: "timers.time-types.seconds"
        }
    }

    func durationSeconds(for value: Double) -> Int {
        switch self {
        case .hours: Int(value * 3600)
        case .minutes: Int(value * 60)
        case .seconds: Int(value)
        }
    }
}

enum DescriptionMarkupFlow {
    static func parseTimerValue(from selection: String) -> Double? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let whole = parseNumber(trimmed), whole > 0 {
            return whole
        }

        let pattern = #"[\d]+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range, in: trimmed) else {
            return nil
        }
        let token = String(trimmed[range])
        guard let value = parseNumber(token), value > 0 else { return nil }
        return value
    }

    static func parseNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    static func eligibleIngredients(
        from ingredients: [IngredientData],
        selectedText: String
    ) -> [IngredientData] {
        let selectedAmount = parseNumber(selectedText.trimmingCharacters(in: .whitespacesAndNewlines))

        return ingredients
            .filter { ingredient in
                guard !ingredient.isSeparator, ingredient.hasQuantity else { return false }
                guard let amount = parseNumber(ingredient.originalAmount), amount != 0 else { return false }
                return true
            }
            .sorted { lhs, rhs in
                func matches(_ ingredient: IngredientData) -> Bool {
                    guard let selectedAmount,
                          let original = parseNumber(ingredient.originalAmount) else { return false }
                    return abs(original - selectedAmount) < 0.01
                }
                let lhsMatch = matches(lhs)
                let rhsMatch = matches(rhs)
                if lhsMatch != rhsMatch { return lhsMatch }
                return lhs.order < rhs.order
            }
    }

    static func shouldPromptRatio(
        selectedText: String,
        ingredient: IngredientData
    ) -> Bool {
        guard let selected = parseNumber(selectedText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let original = parseNumber(ingredient.originalAmount) else {
            return false
        }
        return abs(selected - original) >= 0.01
    }

    static func ratio(for selectedText: String, ingredient: IngredientData) -> Double? {
        guard let selected = parseNumber(selectedText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let original = parseNumber(ingredient.originalAmount),
              original != 0 else {
            return nil
        }
        return selected / original
    }
}

// MARK: - Timer type sheet

struct DescriptionTimerTypeSheet: View {
    let selectedPreview: String
    let parsedValue: Double
    let onSelect: (DescriptionTimerUnit) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(selectedPreview)
                        .appBody()
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(DescriptionTimerUnit.allCases) { unit in
                        Button {
                            onSelect(unit)
                            dismiss()
                        } label: {
                            Text(unit.localizationKey)
                                .appBody()
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .localizedNavigationTitle("editor.mark-as-timer")
            .navigationBarTitleDisplayMode(.inline)
            .appListBodyTypography()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("edit.cancel") { dismiss() }
                        .appToolbarTextButton()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Ingredient picker sheet

struct DescriptionIngredientPickerSheet: View {
    let ingredients: [IngredientData]
    let selectedText: String
    let onSelect: (IngredientData, Double) -> Void
    var onNeedsRatio: (IngredientData) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ingredients) { ingredient in
                Button {
                    if DescriptionMarkupFlow.shouldPromptRatio(selectedText: selectedText, ingredient: ingredient) {
                        onNeedsRatio(ingredient)
                    } else {
                        onSelect(ingredient, 1.0)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Text(ingredient.name)
                            .appBody()
                        Spacer()
                        Text(ingredientRowAmount(ingredient))
                            .appBody()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .localizedNavigationTitle("editor.mark-as-ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .appListBodyTypography()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("edit.cancel") { dismiss() }
                        .appToolbarTextButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func ingredientRowAmount(_ ingredient: IngredientData) -> String {
        let amount = ingredient.originalAmount
        let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if unit.isEmpty { return amount }
        return "\(amount) \(unit)"
    }
}

// MARK: - Ingredient ratio sheet

struct DescriptionIngredientRatioSheet: View {
    let ingredient: IngredientData
    let selectedText: String
    let onSelect: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    private var selectedAmount: Double? {
        DescriptionMarkupFlow.parseNumber(selectedText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var ratioPercent: Int? {
        guard let ratio = DescriptionMarkupFlow.ratio(for: selectedText, ingredient: ingredient) else { return nil }
        return Int((ratio * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(1.0)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ingredients.mark-as-100")
                            .appBody()
                        Text(ingredient.originalAmount)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                }

                if let percent = ratioPercent, let selected = selectedAmount {
                    Button {
                        if let ratio = DescriptionMarkupFlow.ratio(for: selectedText, ingredient: ingredient) {
                            onSelect(ratio)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: String(localized: "ingredients.mark-as-percent"), percent))
                                .appBody()
                            Text(String(format: "%g", selected))
                                .appFootnote()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .localizedNavigationTitle("editor.mark-as-ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .appListBodyTypography()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("edit.cancel") { dismiss() }
                        .appToolbarTextButton()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
