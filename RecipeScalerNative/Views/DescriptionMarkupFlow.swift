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

    static func ingredientDisplayText(originalAmount: String, ratio: Double) -> String {
        guard let numeric = parseNumber(originalAmount) else { return originalAmount }
        return IngredientData.formatScalarNumber(numeric * ratio)
    }

    static func parseDurationSeconds(_ raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intValue = Int(trimmed) { return intValue }
        if let doubleValue = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            return Int(doubleValue.rounded())
        }
        return 0
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

// MARK: - Ingredient markup sheet (picker → ratio in one NavigationStack)

private enum DescriptionIngredientMarkupRoute: Hashable {
    case ratio(String)
}

struct DescriptionIngredientMarkupSheet: View {
    let ingredients: [IngredientData]
    let selectedText: String
    let onComplete: (IngredientData, Double) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ingredients) { ingredient in
                if DescriptionMarkupFlow.shouldPromptRatio(selectedText: selectedText, ingredient: ingredient) {
                    NavigationLink(value: DescriptionIngredientMarkupRoute.ratio(ingredient.id)) {
                        ingredientRow(ingredient)
                    }
                } else {
                    Button {
                        onComplete(ingredient, 1.0)
                        dismiss()
                    } label: {
                        ingredientRow(ingredient)
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
            .navigationDestination(for: DescriptionIngredientMarkupRoute.self) { route in
                if case .ratio(let ingredientId) = route,
                   let ingredient = ingredients.first(where: { $0.id == ingredientId }) {
                    DescriptionIngredientRatioStepView(
                        ingredient: ingredient,
                        selectedText: selectedText
                    ) { ratio in
                        onComplete(ingredient, ratio)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func ingredientRow(_ ingredient: IngredientData) -> some View {
        HStack {
            Text(ingredient.name)
                .appBody()
            Spacer()
            Text(ingredientRowAmount(ingredient))
                .appBody()
                .foregroundStyle(.secondary)
        }
    }

    private func ingredientRowAmount(_ ingredient: IngredientData) -> String {
        let amount = ingredient.originalAmount
        let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if unit.isEmpty { return amount }
        return "\(amount) \(unit)"
    }
}

private struct DescriptionIngredientRatioStepView: View {
    let ingredient: IngredientData
    let selectedText: String
    let onSelect: (Double) -> Void

    private var selectedAmount: Double? {
        DescriptionMarkupFlow.parseNumber(selectedText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var ratioPercent: Int? {
        guard let ratio = DescriptionMarkupFlow.ratio(for: selectedText, ingredient: ingredient) else { return nil }
        return Int((ratio * 100).rounded())
    }

    var body: some View {
        List {
            Button {
                onSelect(1.0)
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
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: Bundle.currentLocalizedString("ingredients.mark-as-percent"), percent))
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
    }
}

// MARK: - Existing node action menus (edit mode)

struct DescriptionTimerNodeMenuState: Identifiable {
    let presentationId: UInt
    let click: DescriptionNodeClick
    let reference: RecipeDescriptionTimerReference

    var id: String { "\(presentationId)-\(click.timerMatchKey)" }
}

struct DescriptionIngredientNodeMenuState: Identifiable {
    let presentationId: UInt
    let click: DescriptionNodeClick
    let ingredient: IngredientData

    var id: String { "\(presentationId)-\(click.ingredientId)" }

    var ratioLabel: String? {
        guard let ratio = Double(click.ratio.replacingOccurrences(of: ",", with: ".")),
              ratio != 1.0 else { return nil }
        return String(format: Bundle.currentLocalizedString("ingredients.mark-as-percent"), Int((ratio * 100).rounded()))
    }

    var menuSubtitle: String {
        if let ratioLabel {
            return "\(ingredient.name), \(ratioLabel)"
        }
        return ingredient.name
    }
}

private enum DescriptionTimerNodeRoute: Hashable {
    case rename
}

struct DescriptionTimerNodeFlowSheet: View {
    let menu: DescriptionTimerNodeMenuState
    let onStart: () -> Void
    let onRenameSave: (String) -> Void
    let onUnlink: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onStart()
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            AppSymbol.toolbarImage("alarm")
                                .foregroundStyle(.primary)
                                .frame(width: 20, height: 20)
                            Text("Start timer")
                                .appHeadline()
                                .foregroundStyle(.primary)
                        }
                        Text(menu.reference.menuSubtitle)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink(value: DescriptionTimerNodeRoute.rename) {
                    Text("timers.rename")
                        .appBody()
                }

                Button(role: .destructive) {
                    onUnlink()
                    dismiss()
                } label: {
                    Text("timers.unlink")
                        .appBody()
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
            .navigationDestination(for: DescriptionTimerNodeRoute.self) { route in
                if case .rename = route {
                    DescriptionTimerRenameStepView(initialName: menu.click.name) { name in
                        onRenameSave(name)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private enum DescriptionIngredientNodeRoute: Hashable {
    case changeRatio
}

struct DescriptionIngredientNodeFlowSheet: View {
    let menu: DescriptionIngredientNodeMenuState
    let onRatioSave: (Double) -> Void
    let onUnlink: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink(value: DescriptionIngredientNodeRoute.changeRatio) {
                    Text("ingredients.change-ratio")
                        .appBody()
                }

                Button(role: .destructive) {
                    onUnlink()
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("timers.unlink-from-value")
                            .appBody()
                        Text(menu.menuSubtitle)
                            .appFootnote()
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
            .navigationDestination(for: DescriptionIngredientNodeRoute.self) { route in
                if case .changeRatio = route {
                    DescriptionIngredientExistingRatioStepView(
                        ingredient: menu.ingredient,
                        currentRatio: Double(menu.click.ratio.replacingOccurrences(of: ",", with: ".")) ?? 1
                    ) { ratio in
                        onRatioSave(ratio)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct DescriptionIngredientExistingRatioStepView: View {
    let ingredient: IngredientData
    let currentRatio: Double
    let onSave: (Double) -> Void

    @State private var amountText = ""

    private var originalAmount: Double? {
        DescriptionMarkupFlow.parseNumber(ingredient.originalAmount)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField("ingredients.ratio-placeholder", text: $amountText)
                        .font(AppTypography.body)
                        .keyboardType(.decimalPad)
                    if let originalAmount {
                        Text(String(format: Bundle.currentLocalizedString("ingredients.of-original"), IngredientData.formatScalarNumber(originalAmount)))
                            .appFootnote()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .appListBodyTypography()
        .localizedNavigationTitle("ingredients.change-ratio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("edit.done") { save() }
                    .appToolbarConfirmButton()
                    .disabled(!canSave)
            }
        }
        .onAppear {
            if let originalAmount {
                amountText = IngredientData.formatScalarNumber(originalAmount * currentRatio)
            }
        }
    }

    private var canSave: Bool {
        guard let originalAmount, originalAmount > 0,
              let entered = DescriptionMarkupFlow.parseNumber(amountText),
              entered > 0 else { return false }
        return true
    }

    private func save() {
        guard let originalAmount, originalAmount > 0,
              let entered = DescriptionMarkupFlow.parseNumber(amountText),
              entered > 0 else { return }
        onSave(entered / originalAmount)
    }
}

private struct DescriptionTimerRenameStepView: View {
    let initialName: String
    let onSave: (String) -> Void

    @State private var name = ""

    var body: some View {
        Form {
            TextField("timers.timer-name", text: $name)
                .font(AppTypography.body)
        }
        .localizedNavigationTitle("timers.rename")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("edit.done") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                }
                .appToolbarConfirmButton()
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            name = initialName
        }
    }
}
