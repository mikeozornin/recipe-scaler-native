import SwiftUI

// MARK: - Focus & keyboard

enum IngredientFieldFocus: Hashable {
    case name(String)
    case amount(String)
    case newName
    case newAmount

    var rowKey: String {
        switch self {
        case .name(let id), .amount(let id): return id
        case .newName, .newAmount: return "new"
        }
    }
}

// MARK: - View mode

struct YDocIngredientsSection: View {
    let ingredients: [IngredientData]
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    var nutritionEnabled: Bool = false
    var nutritionViewMode: IngredientNutritionViewMode = .dish

    private var sorted: [IngredientData] {
        ingredients.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Ingredients"))
                .font(.custom(AppFonts.display, size: 22))
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
                .accessibilityIdentifier(AccessibilityIdentifiers.ingredientsSection)

            if sorted.isEmpty {
                Text(String(localized: "No ingredients"))
                    .font(.custom(AppFonts.sans, size: RecipeRowLayoutMetrics.titleFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sorted, id: \.id) { ingredient in
                        YDocIngredientViewRow(
                            ingredient: ingredient,
                            baseServings: baseServings,
                            viewServings: viewServings,
                            accentColor: accentColor,
                            nutritionEnabled: nutritionEnabled,
                            nutritionViewMode: nutritionViewMode
                        )
                    }
                }
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
            }
        }
    }
}

private struct YDocIngredientViewRow: View {
    let ingredient: IngredientData
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    let nutritionEnabled: Bool
    let nutritionViewMode: IngredientNutritionViewMode

    private var amountText: String {
        ingredient.scaledQuantityText(targetServings: viewServings, baseServings: max(1, baseServings))
    }

    private var nutritionSummary: String? {
        guard nutritionEnabled else { return nil }
        return IngredientNutritionDisplay.summaryLine(
            ingredient: ingredient,
            baseServings: baseServings,
            viewServings: viewServings,
            mode: nutritionViewMode
        )
    }

    var body: some View {
        if ingredient.isHeaderRow {
            IngredientRowHeaderLabel(text: ingredient.name)
        } else {
            ingredientContent
        }
    }

    @ViewBuilder
    private var ingredientContent: some View {
        if nutritionSummary != nil {
            ingredientNameAmountRow(nutritionSummary: nutritionSummary)
                .ingredientListRowChromeCompact()
        } else {
            ingredientNameAmountRow(nutritionSummary: nil)
                .ingredientListRowChrome()
        }
    }

    private func ingredientNameAmountRow(nutritionSummary: String?) -> some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            IngredientRowMarkerSlot(label: nil)

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.custom(AppFonts.sans, size: RecipeRowLayoutMetrics.titleFontSize))
                    .foregroundStyle(.primary)
                    .lineSpacing(RecipeRowLayoutMetrics.wrappedLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let nutritionSummary {
                    Text(nutritionSummary)
                        .font(.custom(AppFonts.sans, size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !amountText.isEmpty {
                Text(amountText)
                    .font(.custom(AppFonts.mono, size: RecipeRowLayoutMetrics.titleFontSize))
                    .foregroundStyle(accentColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .frame(width: RecipeRowLayoutMetrics.amountColumnWidth, alignment: .trailing)
            }
        }
    }
}

// MARK: - Edit mode

struct YDocIngredientsEditSection: View {
    let recipe: RecipeData
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    var nutritionEnabled: Bool = false
    var nutritionViewMode: IngredientNutritionViewMode = .dish
    let onCommit: (IngredientData) async -> Void
    let onSaveNutrition: (String, Double, Double, Double, Double) async -> Void
    let onDelete: (String) async -> Void
    let onAdd: (String, String) async -> Void
    let onReorder: (Int, Int) async -> Void

    @State private var drafts: [String: IngredientDraft] = [:]
    @State private var nutritionSheetTarget: IngredientNutritionTarget?
    @State private var pendingCommitTask: Task<Void, Never>?
    @State private var newName = ""
    @State private var newAmount = ""
    @State private var isAdding = false
    @FocusState private var focusedField: IngredientFieldFocus?

    private var sorted: [IngredientData] {
        recipe.ingredients.sorted { $0.order < $1.order }
    }

    private var numberedRows: [(number: Int?, ingredient: IngredientData)] {
        var index = 0
        return sorted.map { ingredient in
            if ingredient.isHeaderRow {
                return (nil, ingredient)
            }
            index += 1
            return (index, ingredient)
        }
    }

    private var fieldSequence: [IngredientFieldFocus] {
        var fields: [IngredientFieldFocus] = []
        for ingredient in sorted {
            fields.append(.name(ingredient.id))
            if !ingredient.isHeaderRow {
                fields.append(.amount(ingredient.id))
            }
        }
        fields.append(.newName)
        fields.append(.newAmount)
        return fields
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Ingredients"))
                .font(.custom(AppFonts.display, size: 22))
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(numberedRows, id: \.ingredient.id) { row in
                    let ingredient = row.ingredient
                    let draft = drafts[ingredient.id] ?? IngredientDraft(ingredient: ingredient)
                    YDocIngredientEditRow(
                        rowNumber: row.number,
                        ingredient: ingredient,
                        name: bindingName(for: ingredient.id, fallback: draft.name),
                        amount: bindingAmount(for: ingredient.id, fallback: draft.amount),
                        baseServings: baseServings,
                        viewServings: viewServings,
                        accentColor: accentColor,
                        nutritionEnabled: nutritionEnabled,
                        nutritionViewMode: nutritionViewMode,
                        focusedField: $focusedField,
                        onNutritionTap: {
                            nutritionSheetTarget = IngredientNutritionTarget(ingredient: ingredient)
                        },
                        onDelete: {
                            Task { await onDelete(ingredient.id) }
                        },
                        onDropIngredient: { draggedId in
                            reorderDropped(draggedId: draggedId, onto: ingredient.id)
                        }
                    )
                    .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)

                    if ingredient.id != sorted.last?.id {
                        Divider()
                            .padding(.leading, RecipeRowLayoutMetrics.listHorizontalInset)
                    }
                }

                Divider()
                    .padding(.leading, RecipeRowLayoutMetrics.listHorizontalInset)

                YDocNewIngredientRow(
                    name: $newName,
                    amount: $newAmount,
                    accentColor: accentColor,
                    focusedField: $focusedField,
                    onSubmit: {
                        await submitNewIngredient()
                    }
                )
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
            }
        }
        .toolbar {
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        focusPrevious()
                    } label: {
                        AppSymbol.image("chevron.up")
                    }
                    .disabled(!canFocusPrevious)

                    Button {
                        focusNext()
                    } label: {
                        AppSymbol.image("chevron.down")
                    }
                    .disabled(!canFocusNext)

                    Spacer()

                    Button(String(localized: "edit.done")) {
                        focusedField = nil
                    }
                }
            }
        }
        .onAppear { syncDrafts(from: recipe) }
        .onDisappear {
            pendingCommitTask?.cancel()
            pendingCommitTask = nil
        }
        .onChange(of: recipe.ingredients.map(\.id)) { _, _ in syncDrafts(from: recipe) }
        .onChange(of: focusedField) { old, new in
            guard let old, old.rowKey != new?.rowKey else { return }
            pendingCommitTask?.cancel()
            pendingCommitTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                await commitRowLeaving(old.rowKey)
            }
        }
        .sheet(item: $nutritionSheetTarget) { target in
            EditIngredientNutritionSheet(ingredient: target.ingredient) { calories, protein, fat, carbs in
                let ingredientId = target.id
                nutritionSheetTarget = nil
                Task {
                    await onSaveNutrition(ingredientId, calories, protein, fat, carbs)
                }
            }
        }
    }

    private func currentIngredient(for id: String) -> IngredientData? {
        recipe.ingredients.first { $0.id == id }
    }

    private var canFocusPrevious: Bool {
        guard let focusedField,
              let index = fieldSequence.firstIndex(of: focusedField) else { return false }
        return index > 0
    }

    private var canFocusNext: Bool {
        guard let focusedField,
              let index = fieldSequence.firstIndex(of: focusedField) else { return false }
        return index < fieldSequence.count - 1
    }

    private func focusPrevious() {
        guard let focusedField,
              let index = fieldSequence.firstIndex(of: focusedField),
              index > 0 else { return }
        self.focusedField = fieldSequence[index - 1]
    }

    private func focusNext() {
        guard let focusedField,
              let index = fieldSequence.firstIndex(of: focusedField),
              index < fieldSequence.count - 1 else { return }
        self.focusedField = fieldSequence[index + 1]
    }

    private func reorderDropped(draggedId: String, onto targetId: String) {
        guard draggedId != targetId,
              let fromIndex = sorted.firstIndex(where: { $0.id == draggedId }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetId }) else { return }
        Task { await onReorder(fromIndex, toIndex) }
    }

    private func bindingName(for id: String, fallback: String) -> Binding<String> {
        Binding(
            get: { drafts[id]?.name ?? fallback },
            set: { newValue in
                var draft = drafts[id] ?? IngredientDraft(name: fallback, amount: drafts[id]?.amount ?? "")
                draft.name = newValue
                drafts[id] = draft
            }
        )
    }

    private func bindingAmount(for id: String, fallback: String) -> Binding<String> {
        Binding(
            get: { drafts[id]?.amount ?? fallback },
            set: { newValue in
                var draft = drafts[id] ?? IngredientDraft(name: drafts[id]?.name ?? "", amount: fallback)
                draft.amount = newValue
                drafts[id] = draft
            }
        )
    }

    private func syncDrafts(from recipe: RecipeData) {
        var next = drafts
        for ingredient in recipe.ingredients {
            if next[ingredient.id] == nil {
                next[ingredient.id] = IngredientDraft(ingredient: ingredient)
            }
        }
        let ids = Set(recipe.ingredients.map(\.id))
        next = next.filter { ids.contains($0.key) }
        drafts = next
    }

    private func commitRowLeaving(_ rowKey: String) async {
        if rowKey == "new" {
            return
        }
        guard let ingredient = sorted.first(where: { $0.id == rowKey }),
              let draft = drafts[rowKey] else { return }
        let base = currentIngredient(for: ingredient.id) ?? ingredient
        let parsed = IngredientData.parsedQuantity(draft.amount)
        let unchanged =
            draft.name.trimmingCharacters(in: .whitespacesAndNewlines) == base.name &&
            draft.amount.trimmingCharacters(in: .whitespacesAndNewlines) == base.editableQuantity &&
            parsed.originalAmount == (base.originalAmount.isEmpty ? base.amount : base.originalAmount)
        guard !unchanged else { return }
        await commitIngredient(ingredient, name: draft.name, amount: draft.amount)
    }

    private func commitIngredient(_ ingredient: IngredientData, name: String, amount: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let isSeparator = trimmedName.range(of: #"^[-—–−]{2,}$"#, options: .regularExpression) != nil
        let parsed = IngredientData.parsedQuantity(amount)
        let base = currentIngredient(for: ingredient.id) ?? ingredient
        let updated = IngredientData(
            id: base.id,
            name: trimmedName,
            amount: isSeparator ? "" : parsed.originalAmount,
            originalAmount: isSeparator ? "" : parsed.originalAmount,
            unit: isSeparator ? "" : base.preservedUnit(whenParsing: parsed),
            order: base.order,
            isSeparator: isSeparator,
            hasQuantity: isSeparator ? false : parsed.hasQuantity,
            calories: base.calories,
            protein: base.protein,
            fat: base.fat,
            carbs: base.carbs,
            weight: base.weight
        )
        await onCommit(updated)
    }

    private func submitNewIngredient() async {
        guard !isAdding else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isAdding = true
        defer { isAdding = false }
        let amount = newAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        await onAdd(name, amount)
        newName = ""
        newAmount = ""
        focusedField = .newName
    }
}

// MARK: - Row layout (matches RecipeListView box model)

private struct IngredientRowMarkerSlot: View {
    let label: String?

    var body: some View {
        Group {
            if let label {
                Text(label)
                    .font(.custom(AppFonts.sans, size: RecipeRowLayoutMetrics.titleFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(
            width: RecipeRowLayoutMetrics.markerSlotWidth,
            height: RecipeRowLayoutMetrics.titleLineHeight,
            alignment: .trailing
        )
    }
}

private struct IngredientRowHeaderLabel: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            IngredientRowMarkerSlot(label: nil)

            Text(text)
                .font(.custom(AppFonts.sansMedium, size: 14))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ingredientListRowChrome()
    }
}

private struct IngredientNutritionTarget: Identifiable {
    let ingredient: IngredientData

    var id: String { ingredient.id }
}

private struct IngredientDraft {
    var name: String
    var amount: String

    init(ingredient: IngredientData) {
        name = ingredient.name
        amount = ingredient.editableQuantity
    }

    init(name: String, amount: String) {
        self.name = name
        self.amount = amount
    }
}

private struct ExpandingIngredientNameField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.custom(AppFonts.sans, size: RecipeRowLayoutMetrics.titleFontSize))
            .lineSpacing(RecipeRowLayoutMetrics.wrappedLineSpacing)
            .lineLimit(1...)
            .fixedSize(horizontal: false, vertical: true)
            .submitLabel(.next)
    }
}

private struct YDocIngredientEditRow: View {
    let rowNumber: Int?
    let ingredient: IngredientData
    @Binding var name: String
    @Binding var amount: String
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    let nutritionEnabled: Bool
    let nutritionViewMode: IngredientNutritionViewMode
    var focusedField: FocusState<IngredientFieldFocus?>.Binding
    let onNutritionTap: () -> Void
    let onDelete: () -> Void
    let onDropIngredient: (String) -> Void

    private var nutritionSummary: String? {
        guard nutritionEnabled else { return nil }
        return IngredientNutritionDisplay.summaryLine(
            ingredient: ingredient,
            baseServings: baseServings,
            viewServings: viewServings,
            mode: nutritionViewMode
        )
    }

    var body: some View {
        if ingredient.isHeaderRow {
            HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
                IngredientRowMarkerSlot(label: nil)

                ExpandingIngredientNameField(
                    placeholder: String(localized: "edit.ingredient.name"),
                    text: $name
                )
                .focused(focusedField, equals: .name(ingredient.id))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .ingredientListRowChrome()
            .draggable(ingredient.id)
            .dropDestination(for: String.self) { items, _ in
                guard let draggedId = items.first else { return false }
                onDropIngredient(draggedId)
                return true
            }
            .contextMenu {
                Button(role: .destructive, action: onDelete) {
                    AppLabel.make(String(localized: "edit.ingredient.delete"), symbol: "trash")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
                    IngredientRowMarkerSlot(label: rowNumber.map(String.init))

                    ExpandingIngredientNameField(
                        placeholder: String(localized: "edit.ingredient.name"),
                        text: $name
                    )
                    .focused(focusedField, equals: .name(ingredient.id))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextField(String(localized: "edit.ingredient.amount"), text: $amount)
                        .font(.custom(AppFonts.mono, size: RecipeRowLayoutMetrics.titleFontSize))
                        .foregroundStyle(accentColor)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .submitLabel(.next)
                        .frame(width: RecipeRowLayoutMetrics.amountColumnWidth, alignment: .trailing)
                        .focused(focusedField, equals: .amount(ingredient.id))
                }

                if nutritionEnabled {
                    Button(action: onNutritionTap) {
                        HStack(spacing: 4) {
                            if let nutritionSummary {
                                Text(nutritionSummary)
                            } else {
                                Text(String(localized: "nutrition.ingredient.tap-to-edit"))
                            }
                            AppSymbol.image("pencil")
                                .font(.system(size: 11))
                        }
                        .font(.custom(AppFonts.sans, size: 13))
                        .foregroundStyle(.secondary)
                        .underline(pattern: .dot, color: Color.secondary.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, RecipeRowLayoutMetrics.markerSlotWidth + RecipeRowLayoutMetrics.rowMarkerSpacing)
                    .padding(.bottom, RecipeRowLayoutMetrics.nutritionLineBottomInset)
                }
            }
            .modifier(IngredientEditRowChrome(showsNutritionLine: nutritionEnabled))
            .draggable(ingredient.id)
            .dropDestination(for: String.self) { items, _ in
                guard let draggedId = items.first else { return false }
                onDropIngredient(draggedId)
                return true
            }
            .contextMenu {
                Button(role: .destructive, action: onDelete) {
                    AppLabel.make(String(localized: "edit.ingredient.delete"), symbol: "trash")
                }
            }
        }
    }
}

private struct YDocNewIngredientRow: View {
    @Binding var name: String
    @Binding var amount: String
    let accentColor: Color
    var focusedField: FocusState<IngredientFieldFocus?>.Binding
    let onSubmit: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            IngredientRowMarkerSlot(label: "+")

            ExpandingIngredientNameField(
                placeholder: String(localized: "edit.ingredient.name"),
                text: $name
            )
            .focused(focusedField, equals: .newName)
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField(String(localized: "edit.ingredient.amount"), text: $amount)
                .font(.custom(AppFonts.mono, size: RecipeRowLayoutMetrics.titleFontSize))
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: RecipeRowLayoutMetrics.amountColumnWidth, alignment: .trailing)
                .focused(focusedField, equals: .newAmount)

            Button {
                Task { await onSubmit() }
            } label: {
                AppSymbol.image("return")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.borderless)
        }
        .padding(.top, 4)
        .frame(minHeight: RecipeRowLayoutMetrics.rowHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}