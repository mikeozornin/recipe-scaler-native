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

private func numberedIngredientRows(from ingredients: [IngredientData]) -> [(number: Int?, ingredient: IngredientData)] {
    let sorted = ingredients.sorted { $0.order < $1.order }
    var index = 0
    return sorted.map { ingredient in
        if ingredient.isHeaderRow {
            return (nil, ingredient)
        }
        index += 1
        return (index, ingredient)
    }
}

struct YDocIngredientsSection: View {
    let ingredients: [IngredientData]
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    var onScaledQuantityEdited: ((IngredientData, String) -> Void)?
    var onAddIngredientToShopping: ((IngredientData) -> Void)?
    var nutritionEnabled: Bool = false
    var nutritionViewMode: IngredientNutritionViewMode = .dish

    private var numberedRows: [(number: Int?, ingredient: IngredientData)] {
        numberedIngredientRows(from: ingredients)
    }

    private var viewListHeight: CGFloat {
        IngredientEditList.estimatedContentHeight(
            rows: numberedRows,
            nutritionEnabled: nutritionEnabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if numberedRows.isEmpty {
                Text(String(localized: "No ingredients"))
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
                    .padding(.top, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    IngredientColumnHeaderRow()
                        .accessibilityIdentifier(AccessibilityIdentifiers.ingredientsSection)
                        .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)

                    List {
                        ForEach(Array(numberedRows.enumerated()), id: \.element.ingredient.id) { index, row in
                            YDocIngredientViewRow(
                                ingredient: row.ingredient,
                                rowNumber: row.number,
                                baseServings: baseServings,
                                viewServings: viewServings,
                                accentColor: accentColor,
                                onScaledQuantityEdited: onScaledQuantityEdited,
                                onAddToShopping: onAddIngredientToShopping,
                                nutritionEnabled: nutritionEnabled,
                                nutritionViewMode: nutritionViewMode
                            )
                            .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
                            .listRowSeparator(index > 0 ? .visible : .hidden)
                            .listRowBackground(Color(.systemBackground))
                        }
                    }
                    .listStyle(.plain)
                    .listRowSpacing(0)
                    .listSectionSpacing(0)
                    .frame(height: viewListHeight)
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, RecipeRowLayoutMetrics.rowHeight)
                }
            }
        }
    }
}

private func scaledQuantityPreview(amount: String, baseServings: Int, viewServings: Int) -> String {
    let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized), value.isFinite, value > 0 else { return "" }
    let base = max(1, baseServings)
    let factor = Double(max(1, viewServings)) / Double(base)
    return IngredientData.formatScalarNumber(value * factor)
}

private struct YDocIngredientViewRow: View {
    let ingredient: IngredientData
    let rowNumber: Int?
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    var onScaledQuantityEdited: ((IngredientData, String) -> Void)?
    var onAddToShopping: ((IngredientData) -> Void)?
    let nutritionEnabled: Bool
    let nutritionViewMode: IngredientNutritionViewMode

    @State private var scaledDraft = ""
    @FocusState private var isScaledQuantityFocused: Bool

    private var baseQuantityText: String {
        ingredient.quantityText
    }

    private var scaledQuantityText: String {
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

    private var scaledQuantityBinding: Binding<String> {
        Binding(
            get: { isScaledQuantityFocused ? scaledDraft : scaledQuantityText },
            set: { newValue in
                scaledDraft = newValue
                onScaledQuantityEdited?(ingredient, newValue)
            }
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
        ingredientNameAmountRow(nutritionSummary: nutritionSummary)
            .ingredientListRowChrome()
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let onAddToShopping, ShoppingListFromRecipe.isIngredientEligible(ingredient) {
                    Button {
                        onAddToShopping(ingredient)
                    } label: {
                        Label(
                            String(localized: "shopping.ingredient-add"),
                            systemImage: "cart.badge.plus"
                        )
                    }
                    .tint(.green)
                }
            }
    }

    private func ingredientNameAmountRow(nutritionSummary: String?) -> some View {
        IngredientGridRow(
            ingredients: {
                IngredientGridIngredientsColumn(markerLabel: rowNumber.map(String.init)) {
                    VStack(alignment: .leading, spacing: RecipeRowLayoutMetrics.nutritionLineSpacing) {
                        Text(ingredient.name)
                            .appBody()
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let nutritionSummary {
                            Text(nutritionSummary)
                                .appFootnote()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            },
            baseQty: {
                if ingredient.hasQuantity {
                    IngredientMonoQuantityText(text: baseQuantityText, color: .primary)
                }
            },
            scaledQty: {
                if ingredient.hasQuantity {
                    if onScaledQuantityEdited != nil {
                        IngredientScaledQuantityField(
                            text: scaledQuantityBinding,
                            accentColor: accentColor,
                            isFocused: $isScaledQuantityFocused
                        )
                    } else {
                        IngredientMonoQuantityText(text: scaledQuantityText, color: accentColor)
                    }
                }
            },
            trailing: { EmptyView() },
            showsScaledColumn: ingredient.hasQuantity
        )
    }
}

// MARK: - Servings (edit)

/// Base servings row before ingredients — same grid as edit rows, not draggable (web edit `ServingsControl`).
private struct ServingsEditRow: View {
    @Binding var servings: Int
    let scaledPreview: Int
    let accentColor: Color

    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    private var showsScaledPreview: Bool {
        scaledPreview != servings
    }

    var body: some View {
        IngredientGridRow(
            ingredients: {
                IngredientGridIngredientsColumn(markerLabel: nil) {
                    Text(String(localized: "edit.servings"))
                        .font(AppTypography.body)
                        .foregroundStyle(.primary)
                }
            },
            baseQty: {
                TextField("", text: $draftText)
                    .font(AppTypography.mono(AppTypography.bodySize))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .focused($isFocused)
                    .onSubmit(commitDraft)
                    .onChange(of: draftText) { _, _ in
                        guard isFocused, let parsed = RecipeServings.normalize(draftText) else { return }
                        servings = min(99, parsed)
                    }
            },
            scaledQty: {
                if showsScaledPreview {
                    IngredientMonoQuantityText(text: "\(scaledPreview)", color: accentColor)
                }
            },
            trailing: { EmptyView() },
            showsScaledColumn: showsScaledPreview
        )
        .padding(.trailing, RecipeRowLayoutMetrics.listReorderTrailingInset)
        .ingredientListRowChrome()
        .onAppear { draftText = String(servings) }
        .onChange(of: servings) { _, newValue in
            guard !isFocused else { return }
            draftText = String(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commitDraft() }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeEditServingsRow)
    }

    private func commitDraft() {
        if let parsed = RecipeServings.normalize(draftText) {
            servings = min(99, parsed)
        }
        draftText = String(servings)
    }
}

// MARK: - Edit mode

struct YDocIngredientsEditSection: View {
    let recipe: RecipeData
    @Binding var draftServings: Int
    let scaledServingsPreview: Int
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
    @State private var measuredRowHeights: [String: CGFloat] = [:]

    private var sorted: [IngredientData] {
        recipe.ingredients.sorted { $0.order < $1.order }
    }

    private var numberedRows: [(number: Int?, ingredient: IngredientData)] {
        numberedIngredientRows(from: recipe.ingredients)
    }

    private var ingredientRowIds: [String] {
        numberedRows.map(\.ingredient.id)
    }

    private var editListHeight: CGFloat {
        let estimated = IngredientEditList.estimatedContentHeight(
            rows: numberedRows,
            nutritionEnabled: nutritionEnabled
        )
        let measured = IngredientEditList.measuredContentHeight(
            rowIds: ingredientRowIds,
            heights: measuredRowHeights
        )
        // Measured heights omit the «+» row (not in `ingredientRowIds`).
        let measuredWithNewRow = measured > 0
            ? measured + RecipeRowLayoutMetrics.rowHeight + 1
            : 0
        return max(estimated, measuredWithNewRow)
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                IngredientColumnHeaderRow(showsDragHandle: true)

                ServingsEditRow(
                    servings: $draftServings,
                    scaledPreview: scaledServingsPreview,
                    accentColor: accentColor
                )

                List {
                    ForEach(Array(numberedRows.enumerated()), id: \.element.ingredient.id) { _, row in
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
                            }
                        )
                        .listRowInsets(IngredientEditList.rowInsets)
                        .listRowSeparator(.visible)
                        .listRowBackground(Color(.systemBackground))
                    }
                    .onDelete(perform: deleteIngredients)
                    .onMove(perform: moveIngredients)

                    YDocNewIngredientRow(
                        baseServings: baseServings,
                        viewServings: viewServings,
                        name: $newName,
                        amount: $newAmount,
                        accentColor: accentColor,
                        focusedField: $focusedField,
                        onSubmit: {
                            await submitNewIngredient()
                        }
                    )
                    .listRowInsets(IngredientEditList.rowInsets)
                    .listRowSeparator(.visible)
                    .listRowBackground(Color(.systemBackground))
                    .moveDisabled(true)
                    .deleteDisabled(true)
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeEditNewIngredientRow)
                    .id(AccessibilityIdentifiers.recipeEditNewIngredientRow)
                }
                .listStyle(.plain)
                .listRowSpacing(0)
                .listSectionSpacing(0)
                .frame(height: editListHeight)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, RecipeRowLayoutMetrics.rowHeight)
                .environment(\.editMode, .constant(.active))
            }
            .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
        }
        .onPreferenceChange(IngredientEditRowHeightKey.self) { heights in
            measuredRowHeights = heights
        }
        .toolbar {
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        focusPrevious()
                    } label: {
                        AppToolbarStyle.icon("chevron.up")
                    }
                    .appToolbarIconButton()
                    .disabled(!canFocusPrevious)

                    Button {
                        focusNext()
                    } label: {
                        AppToolbarStyle.icon("chevron.down")
                    }
                    .appToolbarIconButton()
                    .disabled(!canFocusNext)

                    Spacer()

                    Button(String(localized: "edit.done")) {
                        focusedField = nil
                    }
                    .appToolbarTextButton()
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

    private func moveIngredients(from source: IndexSet, to destination: Int) {
        guard let fromIndex = source.first else { return }
        var toIndex = destination
        if toIndex > fromIndex { toIndex -= 1 }
        guard fromIndex != toIndex, fromIndex < sorted.count, toIndex < sorted.count else { return }
        Task { await onReorder(fromIndex, toIndex) }
    }

    private func deleteIngredients(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            guard offset < numberedRows.count else { continue }
            let id = numberedRows[offset].ingredient.id
            Task { await onDelete(id) }
        }
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

// MARK: - Row layout (matches web ingredient grid)

private struct IngredientColumnHeaderRow: View {
    var showsDragHandle: Bool = false

    var body: some View {
        IngredientGridRow(
            ingredients: {
                IngredientGridIngredientsColumn(markerLabel: nil) {
                    Text(String(localized: "recipes.ingredient-header"))
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(.primary)
                }
            },
            baseQty: {
                Text(String(localized: "recipes.qty-header"))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(.primary)
            },
            scaledQty: { EmptyView() },
            trailing: { EmptyView() },
            showsScaledColumn: false
        )
        .padding(.trailing, showsDragHandle ? RecipeRowLayoutMetrics.listReorderTrailingInset : 0)
        .frame(minHeight: RecipeRowLayoutMetrics.rowHeight)
    }
}

private struct IngredientScaledQuantityField: View {
    @Binding var text: String
    let accentColor: Color
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField("", text: $text)
            .font(AppTypography.mono(AppTypography.bodySize))
            .foregroundStyle(accentColor)
            .multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .focused(isFocused)
    }
}

private struct IngredientMonoQuantityText: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppTypography.mono(AppTypography.bodySize))
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

enum IngredientEditList {
    /// Ingredient rows: content stops before system ≡; trailing inset is the handle zone.
    static let rowInsets = EdgeInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: RecipeRowLayoutMetrics.listReorderTrailingInset
    )

    static func estimatedRowHeight(ingredient: IngredientData, nutritionEnabled: Bool) -> CGFloat {
        guard !ingredient.isHeaderRow, nutritionEnabled else {
            return RecipeRowLayoutMetrics.rowHeight + 4
        }
        let content = 8
            + RecipeRowLayoutMetrics.ingredientBodyLineHeight
            + RecipeRowLayoutMetrics.nutritionLineSpacing
            + RecipeRowLayoutMetrics.footnoteLineHeight
            + RecipeRowLayoutMetrics.nutritionLineBottomInset
            + 8
        return max(72, content)
    }

    static func estimatedContentHeight(
        rows: [(number: Int?, ingredient: IngredientData)],
        nutritionEnabled: Bool
    ) -> CGFloat {
        guard !rows.isEmpty else { return RecipeRowLayoutMetrics.rowHeight }
        let rowsHeight = rows.reduce(CGFloat.zero) { sum, row in
            sum + estimatedRowHeight(ingredient: row.ingredient, nutritionEnabled: nutritionEnabled)
        }
        let separators = CGFloat(max(0, rows.count)) // includes divider before new row
        return rowsHeight + separators + 12 + RecipeRowLayoutMetrics.rowHeight
    }

    static func measuredContentHeight(rowIds: [String], heights: [String: CGFloat]) -> CGFloat {
        let measured = rowIds.compactMap { heights[$0] }
        guard measured.count == rowIds.count, !measured.isEmpty else { return 0 }
        let rowsHeight = measured.reduce(0, +)
        let separators = CGFloat(max(0, rowIds.count - 1))
        return rowsHeight + separators
    }
}

// MARK: - Ingredient grid columns (marker+name | base qty | scaled)

private struct IngredientGridIngredientsColumn<Content: View>: View {
    let markerLabel: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            IngredientRowMarkerSlot(label: markerLabel)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IngredientGridBaseQty<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: RecipeRowLayoutMetrics.baseQtyColumnWidth, alignment: .trailing)
    }
}

private struct IngredientGridScaledQty<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: RecipeRowLayoutMetrics.scaledQtyColumnMinWidth, alignment: .trailing)
    }
}

private struct IngredientGridRow<Ingredients: View, BaseQty: View, ScaledQty: View, Trailing: View>: View {
    @ViewBuilder var ingredients: () -> Ingredients
    @ViewBuilder var baseQty: () -> BaseQty
    @ViewBuilder var scaledQty: () -> ScaledQty
    @ViewBuilder var trailing: () -> Trailing
    var showsScaledColumn: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.gridIngredientsToQtySpacing) {
            ingredients()
            HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.gridQtyColumnsSpacing) {
                IngredientGridBaseQty(content: baseQty)
                if showsScaledColumn {
                    IngredientGridScaledQty(content: scaledQty)
                }
            }
            trailing()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Row layout (matches RecipeListView box model)

private struct IngredientRowMarkerSlot: View {
    let label: String?

    var body: some View {
        Group {
            if let label {
                Text(label)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(
            width: RecipeRowLayoutMetrics.markerSlotWidth,
            height: RecipeRowLayoutMetrics.ingredientBodyLineHeight,
            alignment: .trailing
        )
    }
}

private struct IngredientRowHeaderLabel: View {
    let text: String

    var body: some View {
        IngredientGridRow(
            ingredients: {
                IngredientGridIngredientsColumn(markerLabel: nil) {
                    Text(text)
                        .font(AppTypography.sansMedium(AppTypography.compactSize))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                }
            },
            baseQty: { EmptyView() },
            scaledQty: { EmptyView() },
            trailing: { EmptyView() },
            showsScaledColumn: false
        )
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
            .font(AppTypography.body)
            .lineSpacing(AppTypography.bodyLineSpacing)
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
        rowBody
            .reportIngredientEditRowHeight(rowId: ingredient.id)
    }

    @ViewBuilder
    private var rowBody: some View {
        if ingredient.isHeaderRow {
            IngredientGridRow(
                ingredients: {
                    IngredientGridIngredientsColumn(markerLabel: nil) {
                        ExpandingIngredientNameField(
                            placeholder: String(localized: "edit.ingredient.name"),
                            text: $name
                        )
                        .focused(focusedField, equals: .name(ingredient.id))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    }
                },
                baseQty: { EmptyView() },
                scaledQty: { EmptyView() },
                trailing: { EmptyView() },
                showsScaledColumn: false
            )
            .ingredientListRowChrome()
        } else {
            IngredientGridRow(
                ingredients: {
                    IngredientGridIngredientsColumn(markerLabel: rowNumber.map(String.init)) {
                        VStack(alignment: .leading, spacing: RecipeRowLayoutMetrics.nutritionLineSpacing) {
                            ExpandingIngredientNameField(
                                placeholder: String(localized: "edit.ingredient.name"),
                                text: $name
                            )
                            .focused(focusedField, equals: .name(ingredient.id))

                            if nutritionEnabled {
                                Button(action: onNutritionTap) {
                                    HStack(spacing: 4) {
                                        if let nutritionSummary {
                                            Text(nutritionSummary)
                                        } else {
                                            Text(String(localized: "nutrition.ingredient.tap-to-edit"))
                                        }
                                        AppSymbol.image("pencil")
                                            .font(AppTypography.footnote)
                                    }
                                    .font(AppTypography.footnote)
                                    .foregroundStyle(.secondary)
                                    .underline(pattern: .dot, color: Color.secondary.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                },
                baseQty: {
                    TextField(String(localized: "edit.ingredient.amount"), text: $amount)
                        .font(AppTypography.mono(AppTypography.bodySize))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .submitLabel(.next)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .focused(focusedField, equals: .amount(ingredient.id))
                },
                scaledQty: {
                    IngredientMonoQuantityText(
                        text: scaledQuantityPreview(
                            amount: amount,
                            baseServings: baseServings,
                            viewServings: viewServings
                        ),
                        color: accentColor
                    )
                },
                trailing: { EmptyView() },
                showsScaledColumn: true
            )
            .ingredientListRowChrome()
        }
    }
}

private struct YDocNewIngredientRow: View {
    let baseServings: Int
    let viewServings: Int
    @Binding var name: String
    @Binding var amount: String
    let accentColor: Color
    var focusedField: FocusState<IngredientFieldFocus?>.Binding
    let onSubmit: () async -> Void

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        IngredientGridRow(
            ingredients: {
                IngredientGridIngredientsColumn(markerLabel: "+") {
                    ExpandingIngredientNameField(
                        placeholder: String(localized: "edit.ingredient.name"),
                        text: $name
                    )
                    .focused(focusedField, equals: .newName)
                }
            },
            baseQty: {
                TextField(String(localized: "edit.ingredient.amount"), text: $amount)
                    .font(AppTypography.mono(AppTypography.bodySize))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .focused(focusedField, equals: .newAmount)
            },
            scaledQty: {
                IngredientMonoQuantityText(
                    text: scaledQuantityPreview(
                        amount: amount,
                        baseServings: baseServings,
                        viewServings: viewServings
                    ),
                    color: accentColor
                )
            },
            trailing: { EmptyView() },
            showsScaledColumn: true
        )
        .ingredientListRowChrome()
        .overlay(alignment: .trailing) {
            Button {
                Task { await onSubmit() }
            } label: {
                AppSymbol.image("return")
                    .font(AppTypography.bodySemibold)
            }
            .frame(
                width: RecipeRowLayoutMetrics.listReorderTrailingInset,
                height: RecipeRowLayoutMetrics.rowHeight
            )
            .disabled(!canSubmit)
            .buttonStyle(.borderless)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeEditNewIngredientSubmit)
        }
        .padding(.trailing, -RecipeRowLayoutMetrics.listReorderTrailingInset)
    }
}