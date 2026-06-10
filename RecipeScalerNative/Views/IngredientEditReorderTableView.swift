import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Reminders-style: trailing swipe delete always on; reorder via long-press lift + drag (no reorder handle).
struct IngredientEditReorderTableView: UIViewRepresentable {
    let rows: [(number: Int?, ingredient: IngredientData)]
    let baseServings: Int
    let viewServings: Int
    let accentColor: Color
    let nutritionEnabled: Bool
    let nutritionViewMode: IngredientNutritionViewMode
    @Binding var drafts: [String: IngredientDraft]
    var focusedField: FocusState<IngredientFieldFocus?>.Binding
    let onNutritionTap: (IngredientData) -> Void
    let onDelete: (String) -> Void
    let onReorder: (Int, Int) -> Void
    var onHeightChange: ((CGFloat) -> Void)?

    private static let dragType = UTType.plainText

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.dragDelegate = context.coordinator
        table.dropDelegate = context.coordinator
        table.dragInteractionEnabled = true
        table.separatorInset = .zero
        table.layoutMargins = .zero
        table.backgroundColor = .systemBackground
        table.isScrollEnabled = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = RecipeRowLayoutMetrics.rowHeight
        table.sectionHeaderTopPadding = 0
        context.coordinator.tableView = table
        context.coordinator.startObservingContentSize(table)
        return table
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.parent = self
        let ids = rows.map(\.ingredient.id).joined(separator: "|")
        if context.coordinator.lastRowSignature != ids {
            if context.coordinator.isReordering {
                context.coordinator.needsDataReload = true
                return
            }
            context.coordinator.lastRowSignature = ids
            context.coordinator.needsDataReload = false
            tableView.reloadData()
            DispatchQueue.main.async {
                context.coordinator.reportContentHeightIfNeeded(for: tableView)
            }
        }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate, UITableViewDropDelegate {
        var parent: IngredientEditReorderTableView
        weak var tableView: UITableView?
        var lastRowSignature = ""
        var lastReportedHeight: CGFloat = -1
        /// True while a drag-drop reorder animation is in flight.
        /// Prevents `updateUIView` from calling `reloadData()` which would snap the row back.
        var isReordering = false
        /// Set when new row data arrives during reordering; triggers one deferred reconfigure after flag clears.
        var needsDataReload = false
        private var contentSizeObservation: NSKeyValueObservation?

        init(parent: IngredientEditReorderTableView) {
            self.parent = parent
        }

        func startObservingContentSize(_ tableView: UITableView) {
            contentSizeObservation = tableView.observe(\.contentSize, options: [.new]) { [weak self] tableView, _ in
                self?.reportContentHeight(tableView)
            }
        }

        // MARK: - Data source

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ingredient")
                ?? UITableViewCell(style: .default, reuseIdentifier: "ingredient")
            cell.selectionStyle = .none
            cell.backgroundColor = .systemBackground
            let horizontal = RecipeRowLayoutMetrics.listHorizontalInset
            cell.layoutMargins = .zero
            cell.preservesSuperviewLayoutMargins = false
            cell.separatorInset = UIEdgeInsets(top: 0, left: horizontal, bottom: 0, right: horizontal)
            configureContentConfiguration(for: cell, at: indexPath)
            return cell
        }

        private func configureContentConfiguration(for cell: UITableViewCell, at indexPath: IndexPath) {
            let row = parent.rows[indexPath.row]
            let ingredient = row.ingredient
            let draft = parent.drafts[ingredient.id] ?? IngredientDraft(ingredient: ingredient)
            let onNutritionTap = parent.onNutritionTap

            cell.contentConfiguration = UIHostingConfiguration {
                IngredientEditTableRowHost(
                    rowNumber: row.number,
                    ingredient: ingredient,
                    name: parent.bindingName(for: ingredient.id, fallback: draft.name),
                    amount: parent.bindingAmount(for: ingredient.id, fallback: draft.amount),
                    baseServings: parent.baseServings,
                    viewServings: parent.viewServings,
                    accentColor: parent.accentColor,
                    nutritionEnabled: parent.nutritionEnabled,
                    nutritionViewMode: parent.nutritionViewMode,
                    focusedField: parent.focusedField,
                    onNutritionTap: { onNutritionTap(ingredient) }
                )
                .reportIngredientEditRowHeight(rowId: ingredient.id)
                .padding(.trailing, RecipeRowLayoutMetrics.editRowQtyToReorderSpacing)
            }
            .margins(.all, 0)
        }

        /// Light-weight row update after reorder — reconfigures cells in-place
        /// without destroying/recreating them (avoids UIHostingConfiguration teardown overhead).
        private func reconfigureAllRows(in tableView: UITableView) {
            let count = parent.rows.count
            guard count > 0, count == tableView.numberOfRows(inSection: 0) else {
                tableView.reloadData()
                return
            }
            let allIndices = IndexSet(integersIn: 0..<count)
            let allPaths = allIndices.map { IndexPath(row: $0, section: 0) }
            tableView.reconfigureRows(at: allPaths)
        }

        // MARK: - Swipe delete

        func tableView(
            _ tableView: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            let id = parent.rows[indexPath.row].ingredient.id
            let deleteTitle = Bundle.currentLocalizedString("edit.ingredient.delete")
            let delete = UIContextualAction(style: .destructive, title: deleteTitle) { _, _, completion in
                self.parent.onDelete(id)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash.fill")
            delete.backgroundColor = .systemRed
            let config = UISwipeActionsConfiguration(actions: [delete])
            config.performsFirstActionWithFullSwipe = false
            return config
        }

        // MARK: - Drag / drop reorder (system lift ghost)

        func tableView(
            _ tableView: UITableView,
            itemsForBeginning session: UIDragSession,
            at indexPath: IndexPath
        ) -> [UIDragItem] {
            let id = parent.rows[indexPath.row].ingredient.id
            let provider = NSItemProvider(object: id as NSString)
            provider.suggestedName = id
            return [UIDragItem(itemProvider: provider)]
        }

        func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
            session.localDragSession != nil
        }

        func tableView(
            _ tableView: UITableView,
            dropSessionDidUpdate session: UIDropSession,
            withDestinationIndexPath destinationIndexPath: IndexPath?
        ) -> UITableViewDropProposal {
            UITableViewDropProposal(operation: .move, intent: .unspecified)
        }

        func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
            guard let destinationIndexPath = coordinator.destinationIndexPath,
                  let item = coordinator.items.first,
                  let sourceIndexPath = item.sourceIndexPath else { return }

            var dest = destinationIndexPath.row
            let source = sourceIndexPath.row
            if dest > source { dest -= 1 }
            guard source != dest, source < parent.rows.count, dest < parent.rows.count else { return }

            isReordering = true
            coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
            parent.onReorder(source, dest)

            // After the Yjs mutation completes (~30-50ms), reconfigure cells in-place.
            // The system drop animation (~300ms) is still playing, hiding the update.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.isReordering = false
                if self.needsDataReload {
                    self.needsDataReload = false
                    if let tableView = self.tableView {
                        let currentIds = self.parent.rows.map(\.ingredient.id).joined(separator: "|")
                        self.lastRowSignature = currentIds
                        self.reconfigureAllRows(in: tableView)
                        self.reportContentHeightIfNeeded(for: tableView)
                    }
                }
            }
        }

        func reportContentHeightIfNeeded(for tableView: UITableView) {
            tableView.layoutIfNeeded()
            reportContentHeight(tableView)
        }

        private func reportContentHeight(_ tableView: UITableView) {
            let height = tableView.contentSize.height
            guard height > 0, abs(height - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = height
            parent.onHeightChange?(height)
        }
    }
}

// MARK: - Bindings bridge (drafts dictionary)

private extension IngredientEditReorderTableView {
    func bindingName(for id: String, fallback: String) -> Binding<String> {
        Binding(
            get: { drafts[id]?.name ?? fallback },
            set: { newValue in
                var draft = drafts[id] ?? IngredientDraft(name: fallback, amount: drafts[id]?.amount ?? "")
                draft.name = newValue
                drafts[id] = draft
            }
        )
    }

    func bindingAmount(for id: String, fallback: String) -> Binding<String> {
        Binding(
            get: { drafts[id]?.amount ?? fallback },
            set: { newValue in
                var draft = drafts[id] ?? IngredientDraft(name: drafts[id]?.name ?? "", amount: fallback)
                draft.amount = newValue
                drafts[id] = draft
            }
        )
    }
}

private struct IngredientEditTableRowHost: View {
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

    var body: some View {
        YDocIngredientEditRow(
            rowNumber: rowNumber,
            ingredient: ingredient,
            name: $name,
            amount: $amount,
            baseServings: baseServings,
            viewServings: viewServings,
            accentColor: accentColor,
            nutritionEnabled: nutritionEnabled,
            nutritionViewMode: nutritionViewMode,
            focusedField: focusedField,
            onNutritionTap: onNutritionTap
        )
    }
}
