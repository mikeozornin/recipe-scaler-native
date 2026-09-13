import SwiftUI

/// Cooking matrix: sticky ingredient column + horizontally scrollable cook columns.
///
/// Row heights are *derived* from measured text heights (ingredient label, cell
/// title) instead of being written back from the rendered rows. Both layers
/// (sticky column and scroll content) read the same `rowHeights`, so they stay
/// aligned and there is no layout feedback loop.
struct ProcessTableGrid: View {
    let table: ProcessTableV1
    let ingredients: [IngredientData]
    let scaleFactor: Double
    let session: ProcessTableCookingSession
    let visibleWidth: CGFloat
    let timerMap: ProcessTableTimerMap
    var onStartTimer: ((ProcessTableTimerChip) -> Void)?

    @State private var ingredientTextHeights: [String: CGFloat] = [:]
    @State private var cellTextHeights: [String: CGFloat] = [:]
    @State private var timerHeaderHeights: [String: CGFloat] = [:]

    private enum Segment: Identifiable {
        case empty(rowId: String)
        case span(ProcessTableSpan, startId: String)

        var id: String {
            switch self {
            case .empty(let rowId): return "empty:\(rowId)"
            case .span(_, let startId): return "span:\(startId)"
            }
        }
    }

    private var rows: [IngredientData] {
        ProcessTableRows.ordered(ingredients: ingredients, rowOrder: table.rowOrder)
    }

    private var cookColumns: [ProcessTableV1.Column] { table.cookColumns }

    private var ingredientWidth: CGFloat {
        max(
            ProcessTableLayout.ingredientColumnMinWidth,
            visibleWidth * ProcessTableLayout.ingredientColumnFraction
        )
    }

    private var cookColumnWidth: CGFloat {
        let remaining = max(0, visibleWidth - ingredientWidth)
        let count = CGFloat(max(cookColumns.count, 1))
        return max(ProcessTableLayout.cookColumnMinWidth, remaining / count)
    }

    private var hasTimerHeader: Bool { !timerMap.byColumnId.isEmpty }

    private var timerHeaderHeight: CGFloat {
        max(ProcessTableLayout.timerHeaderMinHeight, timerHeaderHeights.values.max() ?? 0)
    }

    private var columnSpans: [[ProcessTableSpan]] {
        let rowIds = rows.map(\.id)
        return cookColumns.map { column in
            let filled = rows.map { table.isAssigned(ingredientId: $0.id, columnId: column.id) }
            return ProcessTableMerge.mergeFilledRowsWithCellTitles(
                filled: filled,
                rowIds: rowIds,
                columnId: column.id,
                cellTitles: table.cellTitles
            )
        }
    }

    /// Row heights shared by the sticky column and every cook column.
    private var rowHeights: [String: CGFloat] {
        let rows = self.rows
        var heights: [String: CGFloat] = [:]
        for row in rows {
            let text = (ingredientTextHeights[row.id] ?? 0) + ProcessTableLayout.ingredientRowVerticalPad * 2
            let thumb = ProcessTableLayout.illustrationSlot + ProcessTableLayout.ingredientRowVerticalPad * 2
            heights[row.id] = max(ProcessTableLayout.rowMinHeight, text, thumb)
        }
        for (columnIndex, column) in cookColumns.enumerated() {
            for span in columnSpans[columnIndex] {
                let ids = rows.dropFirst(span.startRow).prefix(span.rowSpan).map(\.id)
                guard let lastId = ids.last, let startId = ids.first else { continue }
                let key = ProcessTableCookingSession.cellKey(columnId: column.id, startIngredientId: startId)
                let needed = (cellTextHeights[key] ?? 0) + ProcessTableLayout.cellTextVerticalPad * 2
                let sum = ids.reduce(0) { $0 + (heights[$1] ?? 0) }
                if needed > sum {
                    heights[lastId, default: 0] += needed - sum
                }
            }
        }
        return heights
    }

    var body: some View {
        let spans = columnSpans
        let heights = rowHeights

        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: ingredientWidth)
                    ForEach(Array(cookColumns.enumerated()), id: \.element.id) { columnIndex, column in
                        VStack(spacing: 0) {
                            if hasTimerHeader {
                                timerHeaderCell(column: column)
                            }
                            ForEach(segments(for: spans[columnIndex])) { segment in
                                switch segment {
                                case .empty(let rowId):
                                    Color.clear
                                        .frame(width: cookColumnWidth, height: heights[rowId] ?? ProcessTableLayout.rowMinHeight)
                                case .span(let span, let startId):
                                    spanCell(
                                        column: column,
                                        columnIndex: columnIndex,
                                        span: span,
                                        startId: startId,
                                        height: spanHeight(span, heights: heights)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeProcessTableGrid)

            VStack(alignment: .leading, spacing: 0) {
                if hasTimerHeader {
                    Color.clear
                        .frame(width: ingredientWidth, height: timerHeaderHeight)
                        .overlay(alignment: .bottom) { hairline }
                }
                ForEach(rows) { ingredient in
                    ingredientCell(ingredient)
                        .frame(
                            width: ingredientWidth,
                            height: heights[ingredient.id] ?? ProcessTableLayout.rowMinHeight,
                            alignment: .topLeading
                        )
                        .overlay(alignment: .bottom) { hairline }
                }
            }
            .background(Color(.systemBackground))
            .padding(.trailing, ProcessTableLayout.stickySeamCover)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Cells

    private var hairline: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: ProcessTableLayout.filledCellBorderWidth)
    }

    private func timerHeaderCell(column: ProcessTableV1.Column) -> some View {
        HStack(spacing: ProcessTableLayout.timerChipGap) {
            ForEach(timerMap.byColumnId[column.id] ?? []) { chip in
                ProcessTableTimerChipButton(chip: chip, onStart: onStartTimer)
            }
        }
        .padding(.horizontal, ProcessTableLayout.cellTextVerticalPad)
        .padding(.vertical, ProcessTableLayout.cellTextVerticalPad)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            commit(height, into: &timerHeaderHeights, key: column.id)
        }
        .frame(width: cookColumnWidth, height: timerHeaderHeight)
        .overlay(alignment: .bottom) { hairline }
    }

    private func spanCell(
        column: ProcessTableV1.Column,
        columnIndex: Int,
        span: ProcessTableSpan,
        startId: String,
        height: CGFloat
    ) -> some View {
        let title = table.resolvedCellTitle(
            columnId: column.id,
            startIngredientId: startId,
            fallback: column.title
        )
        let done = session.isCellDone(columnId: column.id, startIngredientId: startId)
        let key = ProcessTableCookingSession.cellKey(columnId: column.id, startIngredientId: startId)
        let previousFilled = span.startRow > 0
            && table.isAssigned(ingredientId: rows[span.startRow - 1].id, columnId: column.id)
        let needsTopBorder = span.startRow == 0 ? !hasTimerHeader : !previousFilled
        var edges: Edge.Set = [.trailing, .bottom]
        if columnIndex == 0 { edges.insert(.leading) }
        if needsTopBorder { edges.insert(.top) }

        return Button {
            session.toggleCell(columnId: column.id, startIngredientId: startId)
        } label: {
            ZStack(alignment: .topLeading) {
                Text(title)
                    .appBody()
                    .multilineTextAlignment(.center)
                    .strikethrough(done)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: cookColumnWidth - ProcessTableLayout.cellTextHorizontalPad * 2)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight in
                        commit(textHeight, into: &cellTextHeights, key: key)
                    }
                    .frame(width: cookColumnWidth, height: height, alignment: .center)

                checkboxGlyph(done: done)
                    .foregroundStyle(done ? Color.accentColor : Color.secondary)
                    .padding(ProcessTableLayout.cellCheckboxInset)
            }
            .frame(width: cookColumnWidth, height: height)
            .background(Color(uiColor: .secondarySystemFill))
            .overlay(ProcessTableCellBorder(edges: edges))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("recipe.process-table.column-done")
        .accessibilityValue(Text(title))
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    private func ingredientCell(_ ingredient: IngredientData) -> some View {
        let measured = session.measuredIngredientIds.contains(ingredient.id)
        let title = ProcessTableIngredientLabel.display(ingredient, scaleFactor: scaleFactor)
        return Button {
            session.toggleIngredient(ingredient.id)
        } label: {
            HStack(alignment: .top, spacing: ProcessTableLayout.rowCheckboxToThumbGap) {
                checkboxGlyph(done: measured)
                    .foregroundStyle(measured ? Color.accentColor : Color.secondary)
                    .frame(
                        width: ProcessTableLayout.rowCheckboxVisualWidth,
                        height: ProcessTableLayout.illustrationSlot
                    )

                IngredientIllustrationThumb(illustrationId: ingredient.illustrationId)
                    .frame(
                        width: ProcessTableLayout.illustrationSlot,
                        height: ProcessTableLayout.illustrationSlot
                    )
                    .allowsHitTesting(false)

                Text(title)
                    .appBody()
                    .strikethrough(measured)
                    .foregroundStyle(measured ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        commit(height, into: &ingredientTextHeights, key: ingredient.id)
                    }
                    .frame(maxWidth: .infinity, minHeight: ProcessTableLayout.illustrationSlot, alignment: .leading)
            }
            .padding(.vertical, ProcessTableLayout.ingredientRowVerticalPad)
            .padding(.trailing, ProcessTableLayout.ingredientColumnTrailingPad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("recipe.process-table.measured")
        .accessibilityValue(Text(title))
        .accessibilityAddTraits(measured ? .isSelected : [])
    }

    // MARK: - Helpers

    private func segments(for spans: [ProcessTableSpan]) -> [Segment] {
        var out: [Segment] = []
        var index = 0
        let rows = self.rows
        while index < rows.count {
            if let span = spans.first(where: { $0.startRow == index }) {
                out.append(.span(span, startId: rows[index].id))
                index += max(1, span.rowSpan)
            } else {
                out.append(.empty(rowId: rows[index].id))
                index += 1
            }
        }
        return out
    }

    private func spanHeight(_ span: ProcessTableSpan, heights: [String: CGFloat]) -> CGFloat {
        rows.dropFirst(span.startRow).prefix(span.rowSpan)
            .reduce(0) { $0 + (heights[$1.id] ?? ProcessTableLayout.rowMinHeight) }
    }

    /// UIImage-backed body-size SF Symbol so Button's default imageScale cannot inflate it.
    private func checkboxGlyph(done: Bool) -> Image {
        AppSymbol.sizedImage(
            done ? "checkmark.circle.fill" : "circle",
            pointSize: ProcessTableLayout.checkboxPointSize,
            weight: .semibold
        )
    }

    private func commit(_ value: CGFloat, into store: inout [String: CGFloat], key: String) {
        guard value.isFinite, value >= 0 else { return }
        if let current = store[key], abs(current - value) < 0.5 { return }
        store[key] = value
    }

}

/// Name already carries the unit ("…, кг"); amount is the scaled number only.
enum ProcessTableIngredientLabel {
    static func display(_ ingredient: IngredientData, scaleFactor: Double) -> String {
        let amount = scaledNumber(originalAmount: ingredient.originalAmount, scaleFactor: scaleFactor)
        if amount.isEmpty { return ingredient.name }
        return "\(ingredient.name) \(amount)"
    }

    static func scaledNumber(originalAmount: String, scaleFactor: Double) -> String {
        let raw = originalAmount.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(raw), value.isFinite else { return "" }
        return AppNumberFormat.string(value * scaleFactor, maximumFractionDigits: 2)
    }
}

/// Hairline border on selected edges (web: `border-r border-b`, `border-l` on first column,
/// `border-t` when nothing filled above).
private struct ProcessTableCellBorder: View {
    let edges: Edge.Set

    var body: some View {
        let width = ProcessTableLayout.filledCellBorderWidth
        let color = Color.secondary.opacity(0.25)
        ZStack {
            if edges.contains(.top) {
                Rectangle().fill(color).frame(height: width)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            if edges.contains(.bottom) {
                Rectangle().fill(color).frame(height: width)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if edges.contains(.leading) {
                Rectangle().fill(color).frame(width: width)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if edges.contains(.trailing) {
                Rectangle().fill(color).frame(width: width)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    let hash = ProcessTableSourceHash.compute(
        ingredients: [ProcessTableSourceHash.HashIngredient(id: "a", originalAmount: 200, unit: "g")],
        steps: ["Mix"]
    )
    let table = ProcessTableV1(
        version: 1,
        sourceHash: hash,
        columns: [
            .init(id: "prep", title: "Mise", kind: .prep, stepIndex: nil),
            .init(id: "c1", title: "Mix", kind: .cook, stepIndex: 0),
            .init(id: "c2", title: "Bake", kind: .cook, stepIndex: 1),
        ],
        assignments: [
            .init(ingredientId: "a", columnId: "c1"),
            .init(ingredientId: "b", columnId: "c1"),
            .init(ingredientId: "c", columnId: "c1"),
            .init(ingredientId: "d", columnId: "c2"),
        ]
    )
    let ingredients = [
        IngredientData(id: "a", name: "Flour", originalAmount: "200", unit: "g", order: 1),
        IngredientData(id: "b", name: "Water", originalAmount: "120", unit: "g", order: 2),
        IngredientData(id: "c", name: "Salt", originalAmount: "4", unit: "g", order: 3),
        IngredientData(id: "d", name: "Yeast", originalAmount: "3", unit: "g", order: 4),
        IngredientData(id: "e", name: "Oil", originalAmount: "10", unit: "g", order: 5),
    ]
    return ProcessTableGrid(
        table: table,
        ingredients: ingredients,
        scaleFactor: 1,
        session: ProcessTableCookingSession(),
        visibleWidth: 667,
        timerMap: ProcessTableTimerMap(byColumnId: [:], leftover: [])
    )
    .padding(16)
}
