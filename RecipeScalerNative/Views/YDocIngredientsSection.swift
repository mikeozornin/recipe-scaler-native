import RecipeScalerCore
import SwiftUI
import UIKit

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

    @FocusState private var focusedScaledQuantityId: String?
    @State private var measuredRowHeights: [String: CGFloat] = [:]

    private var numberedRows: [(number: Int?, ingredient: IngredientData)] {
        numberedIngredientRows(from: ingredients)
    }

    private var ingredientRowIds: [String] {
        numberedRows.map(\.ingredient.id)
    }

    private var viewListHeight: CGFloat {
        // Mix measured row heights with estimates for rows not yet laid out.
        // All-or-nothing measured height caused a feedback loop: short estimated
        // frame clipped trailing rows → they never reported height → stayed estimated.
        IngredientEditList.resolvedContentHeight(
            rows: numberedRows,
            heights: measuredRowHeights,
            nutritionEnabled: nutritionEnabled,
            includesNewRow: false
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if numberedRows.isEmpty {
                Text("recipes.no-ingredients")
                    .appBody()
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
                                baseServings: baseServings,
                                viewServings: viewServings,
                                accentColor: accentColor,
                                onScaledQuantityEdited: onScaledQuantityEdited,
                                nutritionEnabled: nutritionEnabled,
                                nutritionViewMode: nutritionViewMode,
                                focusedId: $focusedScaledQuantityId
                            )
                            .overlay(alignment: .top) {
                                if index > 0 {
                                    Divider()
                                }
                            }
                            .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color(.systemBackground))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if let onAddIngredientToShopping,
                                   ShoppingListFromRecipe.isIngredientEligible(row.ingredient),
                                   !row.ingredient.isHeaderRow {
                                    Button {
                                        onAddIngredientToShopping(row.ingredient)
                                    } label: {
                                        Label("shopping.ingredient-add", systemImage: "cart.badge.plus")
                                    }
                                    .tint(.green)
                                    .accessibilityIdentifier(AccessibilityIdentifiers.ingredientSwipeAddToShopping)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .listRowSpacing(0)
                    .listSectionSpacing(0)
                    .frame(height: viewListHeight)
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .environment(\.defaultMinListRowHeight, RecipeRowLayoutMetrics.rowHeight)
                }
            }
        }
        .onPreferenceChange(IngredientEditRowHeightKey.self) { heights in
            guard heights != measuredRowHeights else { return }
            measuredRowHeights = heights
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("edit.done") {
                    focusedScaledQuantityId = nil
                }
                .appToolbarTextButton()
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
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    var onScaledQuantityEdited: ((IngredientData, String) -> Void)?
    let nutritionEnabled: Bool
    let nutritionViewMode: IngredientNutritionViewMode
    var focusedId: FocusState<String?>.Binding

    @State private var scaledDraft = ""

    private var isScaledQuantityFocused: Bool {
        focusedId.wrappedValue == ingredient.id
    }

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
        Group {
            if ingredient.isHeaderRow {
                IngredientRowHeaderLabel(text: ingredient.name)
            } else {
                ingredientContent
            }
        }
        .reportIngredientEditRowHeight(rowId: ingredient.id)
    }

    @ViewBuilder
    private var ingredientContent: some View {
        if nutritionSummary != nil {
            ingredientNameAmountRow(nutritionSummary: nutritionSummary)
                .ingredientListRowChromeCompact()
        } else {
            ingredientNameAmountRow(nutritionSummary: nutritionSummary)
                .ingredientListRowChrome()
        }
    }

    private func ingredientNameAmountRow(nutritionSummary: String?) -> some View {
        IngredientGridRow(
            ingredients: {
                IngredientGridIngredientsColumn(
                    leadingSlot: .thumb(
                        illustrationId: ingredient.illustrationId,
                        isInteractive: false,
                        onTap: nil
                    )
                ) {
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
                            focusedId: focusedId,
                            ingredientId: ingredient.id
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

/// Base servings row above ingredient column headers — qty column alignment, not draggable (web `ServingsControl` above `IngredientsSection`).
private struct ServingsEditRow: View {
    @Binding var servings: Int
    let accentColor: Color

    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.gridIngredientsToQtySpacing) {
            Text("edit.servings")
                .appBody()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: $draftText)
                .font(AppTypography.mono(AppTypography.bodySize))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .frame(width: RecipeRowLayoutMetrics.baseQtyColumnWidth, alignment: .trailing)
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onChange(of: draftText) { _, _ in
                    guard isFocused, let parsed = RecipeServings.normalize(draftText) else { return }
                    servings = min(99, parsed)
                }
        }
        .padding(.trailing, RecipeRowLayoutMetrics.editRowQtyToReorderSpacing)
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
    let onIllustrationPickerSelect: (String, String) async -> Void
    let onIllustrationPickerClear: (String) async -> Void
    var onIngredientFieldFocusChanged: ((Bool) -> Void)? = nil
    var onKeyboardDone: (() -> Void)? = nil
    var clearFocusToken: Int = 0

    @State private var drafts: [String: IngredientDraft] = [:]
    @State private var nutritionSheetTarget: IngredientNutritionTarget?
    @State private var newName = ""
    @State private var newAmount = ""
    @State private var isAdding = false
    @FocusState private var focusedField: IngredientFieldFocus?
    @State private var measuredRowHeights: [String: CGFloat] = [:]
    @State private var deleteRevealRowId: String?
    @State private var illustrationPickerTarget: IngredientIllustrationPickerTarget?

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
        // Same hybrid as view mode — partial measurements must still grow the frame.
        IngredientEditList.resolvedContentHeight(
            rows: numberedRows,
            heights: measuredRowHeights,
            nutritionEnabled: nutritionEnabled,
            includesNewRow: false
        )
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
                ServingsEditRow(
                    servings: $draftServings,
                    accentColor: accentColor
                )
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)

                IngredientColumnHeaderRow(showsDragHandle: true, compactLayout: false, showsScaledColumn: false)
                    .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)

                ingredientEditList

                Divider()
                    .padding(.leading, RecipeRowLayoutMetrics.listHorizontalInset)

                YDocNewIngredientRow(
                    baseServings: baseServings,
                    name: $newName,
                    amount: $newAmount,
                    accentColor: accentColor,
                    focusedField: $focusedField,
                    onSubmit: {
                        await submitNewIngredient()
                    }
                )
                .accessibilityIdentifier(AccessibilityIdentifiers.recipeEditNewIngredientRow)
                .id(AccessibilityIdentifiers.recipeEditNewIngredientRow)
            }
        }
        .onPreferenceChange(IngredientEditRowHeightKey.self) { heights in
            guard heights != measuredRowHeights else { return }
            measuredRowHeights = heights
        }
        .onAppear {
            syncDrafts(from: recipe)
        }
        .onChange(of: recipe.ingredients.map(\.id)) { _, _ in syncDrafts(from: recipe) }
        .onChange(of: clearFocusToken) { _, _ in
            focusedField = nil
        }
        .onChange(of: focusedField) { old, new in
            onIngredientFieldFocusChanged?(new != nil)
            guard let old, old.rowKey != new?.rowKey else { return }
            Task {
                await commitRowLeaving(old.rowKey)
            }
        }
        .sheet(item: $illustrationPickerTarget) { target in
            IngredientIllustrationPickerSheet(
                ingredientName: target.name,
                selectedId: target.illustrationId,
                onSelect: { selectedId in
                    let ingredientId = target.ingredientId
                    illustrationPickerTarget = nil
                    Task {
                        if let selectedId {
                            await onIllustrationPickerSelect(ingredientId, selectedId)
                        } else {
                            await onIllustrationPickerClear(ingredientId)
                        }
                    }
                },
                onDismiss: {
                    illustrationPickerTarget = nil
                }
            )
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

                    Color.clear.frame(width: 8)

                    Button {
                        focusNext()
                    } label: {
                        AppToolbarStyle.icon("chevron.down")
                    }
                    .appToolbarIconButton()
                    .disabled(!canFocusNext)

                    Spacer()

                    if focusedField == .newName || focusedField == .newAmount {
                        Button("edit.ingredient.add") {
                            Task { await submitNewIngredient() }
                        }
                        .appToolbarTextButton()
                    } else {
                        Button("edit.done") {
                            onKeyboardDone?()
                            focusedField = nil
                        }
                        .appToolbarTextButton()
                    }
                }
            }
        }
    }

    private var ingredientEditList: some View {
        List {
            ForEach(Array(numberedRows.enumerated()), id: \.element.ingredient.id) { index, row in
                editListRow(for: row)
                    .id(ingredientEditRowIdentity(row.ingredient))
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Divider()
                        }
                    }
                    .listRowInsets(IngredientEditList.rowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(.systemBackground))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteRevealRowId = nil
                            Task { await onDelete(row.ingredient.id) }
                        } label: {
                            Text("edit.ingredient.delete")
                        }
                    }
            }
            .onMove { from, to in
                guard let fromIndex = from.first else { return }
                Task { await onReorder(fromIndex, to) }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .listSectionSpacing(0)
        .frame(height: editListHeight)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, RecipeRowLayoutMetrics.rowHeight)
        .environment(\.editMode, .constant(.active))
    }

    private func editListRow(for row: (number: Int?, ingredient: IngredientData)) -> some View {
        let ingredientId = row.ingredient.id
        let isDeleteRevealed = deleteRevealRowId == ingredientId

        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        deleteRevealRowId = nil
                    }
                    Task { await onDelete(ingredientId) }
                } label: {
                    Text("edit.ingredient.delete")
                        .appHeadline()
                        .foregroundStyle(.white)
                        .frame(maxHeight: .infinity)
                        .frame(width: IngredientEditList.deleteRevealWidth)
                }
                .buttonStyle(.plain)
                .background(Color.red)
            }
            .opacity(isDeleteRevealed ? 1 : 0)

            HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.editListDeleteToContentSpacing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        deleteRevealRowId = isDeleteRevealed ? nil : ingredientId
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: RecipeRowLayoutMetrics.editListDeleteControlSize))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("edit.ingredient.delete"))

                editRow(for: row)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .ingredientEditListRowChrome()
            .offset(x: isDeleteRevealed ? -IngredientEditList.deleteRevealWidth : 0)
        }
        .clipped()
        .reportIngredientEditRowHeight(rowId: ingredientId)
    }

    private func ingredientEditRowIdentity(_ ingredient: IngredientData) -> String {
        "\(ingredient.id)|\(ingredient.illustrationId ?? "")|\(ingredient.illustrationPickerCleared)"
    }

    private func editRow(for row: (number: Int?, ingredient: IngredientData)) -> some View {
        let ingredient = row.ingredient
        let draft = drafts[ingredient.id] ?? IngredientDraft(ingredient: ingredient)
        return YDocIngredientEditRow(
            ingredient: ingredient,
            name: bindingName(for: ingredient.id, fallback: draft.name),
            amount: bindingAmount(for: ingredient.id, fallback: draft.amount),
            baseServings: baseServings,
            viewServings: viewServings,
            accentColor: accentColor,
            nutritionEnabled: nutritionEnabled,
            nutritionViewMode: nutritionViewMode,
            focusedField: $focusedField,
            appliesRowChrome: false,
            onNutritionTap: { nutritionSheetTarget = IngredientNutritionTarget(ingredient: ingredient) },
            onIllustrationTap: {
                illustrationPickerTarget = IngredientIllustrationPickerTarget(
                    ingredientId: ingredient.id,
                    name: draft.name.isEmpty ? ingredient.name : draft.name,
                    illustrationId: ingredient.illustrationId
                )
            }
        )
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
            weight: base.weight,
            illustrationId: base.illustrationId,
            illustrationPickerCleared: base.illustrationPickerCleared
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
    /// When true, skip the marker slot (edit mode without row numbers).
    var compactLayout: Bool = false
    /// Reserve scaled qty slot so «Qty» aligns with base amounts (view mode). Edit keeps one amount column.
    var showsScaledColumn: Bool = true

    var body: some View {
        Group {
            if compactLayout {
                HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.gridIngredientsToQtySpacing) {
                    Text("recipes.ingredient-header")
                        .appHeadline()
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("recipes.qty-header")
                        .appHeadline()
                        .foregroundStyle(.primary)
                        .frame(width: RecipeRowLayoutMetrics.baseQtyColumnWidth, alignment: .trailing)
                }
            } else {
                IngredientGridRow(
                    ingredients: {
                        IngredientGridIngredientsColumn(leadingSlot: nil) {
                            Text("recipes.ingredient-header")
                                .appHeadline()
                                .foregroundStyle(.primary)
                        }
                    },
                    baseQty: {
                        Text("recipes.qty-header")
                            .appHeadline()
                            .foregroundStyle(.primary)
                    },
                    scaledQty: { Color.clear },
                    trailing: { EmptyView() },
                    showsScaledColumn: showsScaledColumn
                )
            }
        }
        // Edit List steals trailing width for reorder; view mode matches list row insets (no extra pad).
        .padding(.trailing, showsDragHandle ? RecipeRowLayoutMetrics.editGridTrailingPadding : 0)
        .frame(minHeight: RecipeRowLayoutMetrics.rowHeight)
    }
}

private struct IngredientScaledQuantityField: View {
    @Binding var text: String
    let accentColor: Color
    var focusedId: FocusState<String?>.Binding
    let ingredientId: String

    var body: some View {
        TextField("", text: $text)
            .font(AppTypography.mono(AppTypography.bodySize))
            .foregroundStyle(accentColor)
            .multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .focused(focusedId, equals: ingredientId)
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
    /// Edit `List` row insets: leading matches servings row (`listHorizontalInset`), trailing gap before reorder.
    /// Trailing delete affordance width when minus reveals delete (matches swipe action).
    static let deleteRevealWidth: CGFloat = 80

    static let rowInsets = EdgeInsets(
        top: 0,
        leading: RecipeRowLayoutMetrics.listHorizontalInset,
        bottom: 0,
        trailing: RecipeRowLayoutMetrics.editRowQtyToReorderSpacing
    )

    static func estimatedRowHeight(ingredient: IngredientData, nutritionEnabled: Bool) -> CGFloat {
        let pad = RecipeRowLayoutMetrics.ingredientRowVerticalPadding
        if ingredient.isHeaderRow {
            return pad + RecipeRowLayoutMetrics.ingredientBodyLineHeight + pad
        }
        guard nutritionEnabled else {
            return pad + RecipeRowLayoutMetrics.ingredientBodyLineHeight + pad
        }
        // Dotted-underline nutrition button is slightly taller than bare footnote line height.
        let content = RecipeRowLayoutMetrics.ingredientBodyLineHeight
            + RecipeRowLayoutMetrics.nutritionLineSpacing
            + RecipeRowLayoutMetrics.footnoteLineHeight
            + 2
        return pad + content + pad
    }

    static func estimatedContentHeight(
        rows: [(number: Int?, ingredient: IngredientData)],
        nutritionEnabled: Bool,
        includesNewRow: Bool = false
    ) -> CGFloat {
        guard !rows.isEmpty else {
            return includesNewRow ? RecipeRowLayoutMetrics.rowHeight + 12 : RecipeRowLayoutMetrics.rowHeight
        }
        let rowsHeight = rows.reduce(CGFloat.zero) { sum, row in
            sum + estimatedRowHeight(ingredient: row.ingredient, nutritionEnabled: nutritionEnabled)
        }
        let separators = CGFloat(max(0, rows.count - 1))
        if includesNewRow {
            return rowsHeight + separators + 12 + RecipeRowLayoutMetrics.rowHeight
        }
        return rowsHeight + separators
    }

    static func measuredContentHeight(rowIds: [String], heights: [String: CGFloat]) -> CGFloat {
        let measured = rowIds.compactMap { heights[$0] }
        guard measured.count == rowIds.count, !measured.isEmpty else { return 0 }
        let rowsHeight = measured.reduce(0, +)
        let separators = CGFloat(max(0, rowIds.count - 1))
        return rowsHeight + separators
    }

    /// Measured height when available; otherwise `estimatedRowHeight` for that row.
    /// Avoids the all-or-nothing trap where a short estimated `List` frame clips trailing
    /// rows so they never report a preference and the height never grows.
    static func resolvedContentHeight(
        rows: [(number: Int?, ingredient: IngredientData)],
        heights: [String: CGFloat],
        nutritionEnabled: Bool,
        includesNewRow: Bool = false
    ) -> CGFloat {
        guard !rows.isEmpty else {
            return includesNewRow ? RecipeRowLayoutMetrics.rowHeight + 12 : RecipeRowLayoutMetrics.rowHeight
        }
        let rowsHeight = rows.reduce(CGFloat.zero) { sum, row in
            if let measured = heights[row.ingredient.id], measured > 0 {
                return sum + measured
            }
            return sum + estimatedRowHeight(ingredient: row.ingredient, nutritionEnabled: nutritionEnabled)
        }
        let separators = CGFloat(max(0, rows.count - 1))
        if includesNewRow {
            return rowsHeight + separators + 12 + RecipeRowLayoutMetrics.rowHeight
        }
        return rowsHeight + separators
    }
}

// MARK: - Ingredient grid columns (marker+name | base qty | scaled)

private struct IngredientGridIngredientsColumn<Content: View>: View {
    let leadingSlot: IngredientIllustrationSlot.Content?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.ingredientMarkerSpacing) {
            if let leadingSlot {
                IngredientIllustrationSlot(content: leadingSlot)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IngredientGridBaseQty<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Color.clear keeps width when content is EmptyView (EmptyView+.frame collapses to 0).
        ZStack(alignment: .trailing) {
            Color.clear
            content()
        }
        .frame(width: RecipeRowLayoutMetrics.baseQtyColumnWidth, alignment: .trailing)
    }
}

private struct IngredientGridScaledQty<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Color.clear keeps width when content is EmptyView (EmptyView+.frame collapses to 0).
        ZStack(alignment: .trailing) {
            Color.clear
            content()
        }
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

private enum IngredientHeaderLabelStyle {
    static let fontSize = AppTypography.bodySize
    /// 2% of body size (0.02 em).
    static let letterSpacing = fontSize * 0.02
    static var font: Font { AppTypography.sansMedium(fontSize) }
}

private struct IngredientRowHeaderLabel: View {
    let text: String

    var body: some View {
        IngredientGridRow(
            ingredients: {
                // No illustration slot — section headers align with the icon’s leading edge, not the name.
                IngredientGridIngredientsColumn(leadingSlot: nil) {
                    Text(text)
                        .font(IngredientHeaderLabelStyle.font)
                        .textCase(.uppercase)
                        .tracking(IngredientHeaderLabelStyle.letterSpacing)
                        .foregroundStyle(.primary)
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

struct IngredientDraft {
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
    let placeholderKey: String
    @Binding var text: String
    var font: Font = AppTypography.body
    var tracking: CGFloat = 0
    @Environment(\.locale) private var locale

    private var resolvedPlaceholder: String {
        _ = locale
        return Bundle.currentLocalizedString(placeholderKey)
    }

    /// Drives row height from text/placeholder metrics — empty `TextField` placeholder is taller than body line.
    private var sizingText: String {
        text.isEmpty ? resolvedPlaceholder : text
    }

    var body: some View {
        Text(sizingText)
            .font(font)
            .tracking(tracking)
            .lineSpacing(AppTypography.bodyLineSpacing)
            .lineLimit(1...)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay(alignment: .topLeading) {
                TextField(resolvedPlaceholder, text: $text, axis: .vertical)
                    .font(font)
                    .tracking(tracking)
                    .lineSpacing(AppTypography.bodyLineSpacing)
                    .lineLimit(1...)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .submitLabel(.next)
            }
    }
}

private struct IngredientIllustrationPickerTarget: Identifiable {
    let ingredientId: String
    let name: String
    let illustrationId: String?

    var id: String { ingredientId }
}

struct YDocIngredientEditRow: View {
    let ingredient: IngredientData
    @Binding var name: String
    @Binding var amount: String
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    let nutritionEnabled: Bool
    let nutritionViewMode: IngredientNutritionViewMode
    var focusedField: FocusState<IngredientFieldFocus?>.Binding
    var appliesRowChrome: Bool = true
    let onNutritionTap: () -> Void
    var onIllustrationTap: (() -> Void)? = nil

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
            HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.gridIngredientsToQtySpacing) {
                ExpandingIngredientNameField(
                    placeholderKey: "edit.ingredient.name",
                    text: $name,
                    font: IngredientHeaderLabelStyle.font,
                    tracking: IngredientHeaderLabelStyle.letterSpacing
                )
                .focused(focusedField, equals: .name(ingredient.id))
                .textCase(.uppercase)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .modifier(IngredientEditRowChrome(applies: appliesRowChrome))
        } else {
            IngredientGridRow(
                ingredients: {
                    IngredientGridIngredientsColumn(
                        leadingSlot: .thumb(
                            illustrationId: ingredient.illustrationId,
                            isInteractive: onIllustrationTap != nil,
                            onTap: onIllustrationTap
                        )
                    ) {
                        VStack(alignment: .leading, spacing: RecipeRowLayoutMetrics.nutritionLineSpacing) {
                            ExpandingIngredientNameField(
                                placeholderKey: "edit.ingredient.name",
                                text: $name
                            )
                            .focused(focusedField, equals: .name(ingredient.id))

                            if nutritionEnabled {
                                Button(action: onNutritionTap) {
                                    HStack(spacing: 4) {
                                        if let nutritionSummary {
                                            Text(nutritionSummary)
                                                .appFootnote()
                                        } else {
                                            Text("nutrition.ingredient.tap-to-edit")
                                                .appFootnote()
                                        }
                                        AppSymbol.image("pencil")
                                            .font(AppTypography.footnote)
                                    }
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
                    TextField("edit.ingredient.amount", text: $amount)
                        .font(AppTypography.mono(AppTypography.bodySize))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .submitLabel(.next)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .focused(focusedField, equals: .amount(ingredient.id))
                },
                scaledQty: { EmptyView() },
                trailing: { EmptyView() },
                showsScaledColumn: false
            )
            .modifier(IngredientEditRowChrome(applies: appliesRowChrome))
        }
    }
}

private struct IngredientEditRowChrome: ViewModifier {
    let applies: Bool

    func body(content: Content) -> some View {
        if applies {
            content.ingredientListRowChrome()
        } else {
            content
        }
    }
}

private struct YDocNewIngredientRow: View {
    let baseServings: Int
    @Binding var name: String
    @Binding var amount: String
    let accentColor: Color
    var focusedField: FocusState<IngredientFieldFocus?>.Binding
    let onSubmit: () async -> Void

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.editListDeleteToContentSpacing) {
            Text("+")
                .appBody()
                .foregroundStyle(.secondary)
                .frame(
                    width: RecipeRowLayoutMetrics.editListDeleteControlSize,
                    height: RecipeRowLayoutMetrics.ingredientBodyLineHeight,
                    alignment: .center
                )

            IngredientGridRow(
                ingredients: {
                    IngredientGridIngredientsColumn(leadingSlot: .empty) {
                        ExpandingIngredientNameField(
                            placeholderKey: "edit.ingredient.name",
                            text: $name
                        )
                        .padding(.leading, RecipeRowLayoutMetrics.editListNewRowNameLeadingInset)
                        .focused(focusedField, equals: .newName)
                    }
                },
                baseQty: {
                    TextField("edit.ingredient.amount", text: $amount)
                        .font(AppTypography.mono(AppTypography.bodySize))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .minimumScaleFactor(0.85)
                        .frame(
                            minHeight: RecipeRowLayoutMetrics.ingredientBodyLineHeight,
                            alignment: .trailing
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .focused(focusedField, equals: .newAmount)
                },
                scaledQty: { EmptyView() },
                trailing: { EmptyView() },
                showsScaledColumn: false
            )
        }
        .padding(.leading, RecipeRowLayoutMetrics.listHorizontalInset)
        .padding(.trailing, RecipeRowLayoutMetrics.editGridTrailingPadding)
        .ingredientEditListRowChrome()
        .overlay(alignment: .topTrailing) {
            Button {
                Task { await onSubmit() }
            } label: {
                AppSymbol.image("return")
                    .font(AppTypography.bodySemibold)
            }
            .frame(
                width: RecipeRowLayoutMetrics.editListReorderControlWidth,
                height: RecipeRowLayoutMetrics.editListDeleteControlSize,
                alignment: .center
            )
            .padding(.top, RecipeRowLayoutMetrics.editListReorderControlTopOffset)
            .disabled(!canSubmit)
            .buttonStyle(.borderless)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeEditNewIngredientSubmit)
        }
    }
}