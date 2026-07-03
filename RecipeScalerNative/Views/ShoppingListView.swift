//
//  ShoppingListView.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

enum ToBuyPurchasePhase: Equatable {
    case staging
    case exiting
}

private enum ShoppingPurchaseTiming {
    static let stageSeconds: TimeInterval = 1.0
    static let exitSeconds: TimeInterval = 0.4
}

struct ShoppingListView: View {
    @Environment(YjsSyncService.self) private var syncService
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelIsCollapsed) private var mobileTimerPanelIsCollapsed
    @Binding var path: NavigationPath
    @State private var bottomDraft = ""
    @State private var inlineEditItemId: String?
    @State private var inlineEditDraft = ""
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var purchasePhases: [String: ToBuyPurchasePhase] = [:]
    @State private var shoppingModel = ShoppingViewModel()
    /// Skips blur-commit when Return dismisses focus before `onSubmit` finishes.
    @State private var suppressAddFieldBlurCommit = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case bottom
        case inline(String)
    }

    private var snapshot: ShoppingListSnapshot {
        syncService.shoppingSnapshot
    }

    private var isOnline: Bool {
        syncService.connectionState == .connected
    }

    private var toBuy: [ShoppingListItem] {
        shoppingModel.sortedToBuy
    }

    private var purchased: [ShoppingListItem] {
        shoppingModel.sortedPurchased
    }

    var body: some View {
        NavigationStack(path: $path) {
            shoppingListScreen
        }
    }

    private var shoppingListScreen: some View {
        Group {
            shoppingList
        }
        .localizedNavigationTitle("shopping.title")
        .appListBodyTypography()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    AppToolbarStyle.labeledIcon(
                        systemName: "square.and.arrow.up",
                        title: "shopping.share-button"
                    )
                }
                .appToolbarIconButton()
                .accessibilityIdentifier(AccessibilityIdentifiers.shoppingShareButton)
            }
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .bottom {
                        Button("shopping.add") {
                            submitBottomDraftFromKeyboard()
                        }
                        .appToolbarTextButton()
                    }
                    Spacer()
                    Button("edit.done") {
                        dismissShoppingKeyboard()
                    }
                    .appToolbarTextButton()
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.shoppingList)
        #if DEBUG
        .onAppear {
            if DebugLaunchOptions.simulateErrorAlert {
                errorMessage = Bundle.currentLocalizedString("auth.error.network")
            }
            if DebugLaunchOptions.openShoppingShare || DebugLaunchOptions.shoppingShareAutoCopyText {
                showShareSheet = true
            }
        }
        #endif
        .sheet(isPresented: $showShareSheet) {
            ShoppingListShareSheet(isOnline: isOnline)
                .environment(syncService)
        }
        .errorAlert(message: $errorMessage)
        .task {
            shoppingModel.recompute(snapshot: snapshot, purchasePhases: purchasePhases)
        }
        .onChange(of: snapshot) { _, newValue in
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                shoppingModel.recompute(snapshot: newValue, purchasePhases: purchasePhases)
            }
        }
        .onChange(of: purchasePhases) { _, newValue in
            shoppingModel.recompute(snapshot: snapshot, purchasePhases: newValue)
        }
    }

    private var shoppingList: some View {
        listContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                shoppingAddBar
            }
    }

    private var listContent: some View {
        List {
            Section {
                shoppingSortControl
                    .sortControlRow()
            }

            Section {
                AppSectionHeader("shopping.section.to-buy")
                    .shoppingSectionLabelRow()
                if toBuy.isEmpty {
                    emptyToBuyContent
                }
                ForEach(toBuy) { item in
                    toBuyRow(item)
                }
                .onDelete(perform: deleteToBuy)
            }

            if !purchased.isEmpty {
                Section {
                    purchasedSectionHeader
                        .shoppingSectionLabelRow()
                    ForEach(purchased) { item in
                        shoppingRow(item, allowsInlineEdit: false, purchasePhase: nil)
                    }
                    .onDelete(perform: deletePurchased)
                }
            }

            if MobileTimerPanelListChrome.needsSpacer(
                timerManager: timerManager,
                isCollapsed: mobileTimerPanelIsCollapsed
            ) {
                MobileTimerPanelListSpacerRow()
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .animation(.easeInOut(duration: ShoppingPurchaseTiming.exitSeconds), value: purchasePhases)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private var shoppingSortControl: some View {
        AppSegmentedControl(
            segments: [
                .init(value: ShoppingSortMode.recipe, title: "shopping.sort.by-recipe"),
                .init(value: ShoppingSortMode.alphabet, title: "shopping.sort.az"),
            ],
            selection: sortBinding,
            style: .listHeader
        )
        .accessibilityLabel("shopping.sort")
    }

    private var purchasedSectionHeader: some View {
        HStack {
            AppSectionHeader("shopping.section.purchased")
            Spacer()
            Button("shopping.clear-bought") {
                Task {
                    await runShoppingMutation { try await syncService.clearPurchasedShoppingItems() }
                }
            }
            .font(AppTypography.subheadline)
            .foregroundStyle(Color.accentColor)
        }
    }

    private var emptyToBuyContent: some View {
        VStack(spacing: 12) {
            AppEmptyStateIllustration(
                asset: purchased.isEmpty ? .shoppingBasketEmpty : .shoppingBasketFull
            )
            Text(
                purchased.isEmpty
                    ? "shopping.empty-to-buy"
                    : "shopping.empty-to-buy-all-done"
            )
            .appBody()
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 348, alignment: .center)
        .listRowBackground(Color.clear)
    }

    // MARK: - Rows

    @ViewBuilder
    private func toBuyRow(_ item: ShoppingListItem) -> some View {
        let phase = purchasePhases[item.id]
        Group {
            if inlineEditItemId == item.id, isManualItem(item) {
                inlineEditRow(item)
            } else {
                shoppingRow(item, allowsInlineEdit: true, purchasePhase: phase)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isManualItem(item), phase == nil else { return }
                        inlineEditItemId = item.id
                        inlineEditDraft = item.label
                        focusedField = .inline(item.id)
                    }
            }
        }
        .opacity(phase == .exiting ? 0 : 1)
        .frame(maxHeight: phase == .exiting ? 0 : nil, alignment: .top)
        .clipped()
        .allowsHitTesting(phase != .exiting)
    }

    private func inlineEditRow(_ item: ShoppingListItem) -> some View {
        HStack(spacing: 12) {
            AppSymbol.image("circle")
                .foregroundStyle(.secondary)
            TextField(String(localized: "shopping.add.placeholder"), text: $inlineEditDraft)
                .font(AppTypography.body)
                .focused($focusedField, equals: .inline(item.id))
                .submitLabel(.done)
                .onSubmit { commitInlineEdit(itemId: item.id) }
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue != .inline(item.id) {
                commitInlineEdit(itemId: item.id)
            }
        }
    }

    /// Pinned below the list so `TextField` identity survives row inserts and list reloads.
    private var shoppingAddBar: some View {
        HStack(spacing: 12) {
            AppSymbol.image("plus")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
            ShoppingListAddTextField(
                text: $bottomDraft,
                isFocused: Binding(
                    get: { focusedField == .bottom },
                    set: { newValue in
                        if newValue {
                            focusedField = .bottom
                        } else if focusedField == .bottom {
                            focusedField = nil
                        }
                    }
                ),
                onAdd: { submitBottomDraftFromKeyboard() }
            )
        }
        .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .top) { Divider() }
        .onChange(of: focusedField) { _, newValue in
            guard newValue != .bottom else { return }
            guard !suppressAddFieldBlurCommit else { return }
            commitBottomDraft()
        }
    }

    @ViewBuilder
    private func shoppingRow(
        _ item: ShoppingListItem,
        allowsInlineEdit: Bool,
        purchasePhase: ToBuyPurchasePhase?
    ) -> some View {
        let showChecked = item.purchased || purchasePhase == .staging || purchasePhase == .exiting
        HStack(alignment: .top, spacing: 12) {
            Button {
                handlePurchaseToggle(item: item, phase: purchasePhase)
            } label: {
                AppSymbol.image(showChecked ? "checkmark.circle" : "circle")
                    .foregroundStyle(Color.primary)
                    .opacity(showChecked ? 0.5 : 1)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(purchasePhase == .exiting)
            .accessibilityLabel(
                showChecked
                    ? String(localized: "shopping.mark-not-purchased")
                    : String(localized: "shopping.mark-purchased")
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .appBody()
                    .strikethrough(showChecked)
                if !item.recipeName.isEmpty {
                    Text(item.recipeName)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(showChecked ? 0.5 : 1)
        }
    }

    // MARK: - Actions

    private var sortBinding: Binding<ShoppingSortMode> {
        Binding(
            get: { snapshot.meta.sortMode },
            set: { mode in
                Task { try? await syncService.setShoppingSortMode(mode) }
            }
        )
    }

    private func isManualItem(_ item: ShoppingListItem) -> Bool {
        item.recipeId == nil && item.ingredientId == nil
    }

    private func handlePurchaseToggle(item: ShoppingListItem, phase: ToBuyPurchasePhase?) {
        if let phase {
            if phase == .staging {
                purchasePhases.removeValue(forKey: item.id)
            }
            return
        }

        #if os(iOS)
        if item.purchased {
            UISelectionFeedbackGenerator().selectionChanged()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        #endif

        if item.purchased {
            Task {
                await runShoppingMutation {
                    try await syncService.setShoppingItemPurchased(id: item.id, purchased: false)
                }
            }
            return
        }

        purchasePhases[item.id] = .staging
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(ShoppingPurchaseTiming.stageSeconds * 1_000_000_000))
            guard purchasePhases[item.id] == .staging else { return }
            purchasePhases[item.id] = .exiting
            try? await Task.sleep(nanoseconds: UInt64(ShoppingPurchaseTiming.exitSeconds * 1_000_000_000))
            guard purchasePhases[item.id] == .exiting else { return }
            purchasePhases.removeValue(forKey: item.id)
            await runShoppingMutation {
                try await syncService.setShoppingItemPurchased(id: item.id, purchased: true)
            }
        }
    }

    private func dismissShoppingKeyboard() {
        switch focusedField {
        case .bottom:
            suppressAddFieldBlurCommit = false
            commitBottomDraft()
            focusedField = nil
        case .inline(let id):
            commitInlineEdit(itemId: id)
            focusedField = nil
        case nil:
            break
        }
    }

    private func submitBottomDraftFromKeyboard() {
        suppressAddFieldBlurCommit = true
        commitBottomDraft()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            suppressAddFieldBlurCommit = false
        }
    }

    private func commitBottomDraft() {
        let text = bottomDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        bottomDraft = ""
        guard !text.isEmpty else { return }

        let pending = shoppingModel.appendPendingManual(label: text)
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            shoppingModel.recompute(snapshot: snapshot, purchasePhases: purchasePhases)
        }

        Task { @MainActor in
            do {
                try await syncService.addManualShoppingItem(label: text)
            } catch {
                shoppingModel.removePendingManual(id: pending.id)
                shoppingModel.recompute(snapshot: snapshot, purchasePhases: purchasePhases)
                if bottomDraft.isEmpty {
                    bottomDraft = text
                }
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }

    private func commitInlineEdit(itemId: String) {
        guard inlineEditItemId == itemId else { return }
        let draft = inlineEditDraft
        inlineEditItemId = nil
        inlineEditDraft = ""
        Task {
            await runShoppingMutation {
                try await syncService.updateShoppingItemLabel(id: itemId, label: draft)
            }
        }
    }

    private func runShoppingMutation(_ operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func deleteToBuy(at offsets: IndexSet) {
        delete(items: toBuy, at: offsets)
    }

    private func deletePurchased(at offsets: IndexSet) {
        delete(items: purchased, at: offsets)
    }

    private func delete(items: [ShoppingListItem], at offsets: IndexSet) {
        for index in offsets {
            let id = items[index].id
            purchasePhases.removeValue(forKey: id)
            if inlineEditItemId == id {
                inlineEditItemId = nil
            }
            Task {
                await runShoppingMutation { try await syncService.removeShoppingItem(id: id) }
            }
        }
    }
}

// MARK: - Add field (localized Return title «Добавить», keyboard stays up on Return)

private struct ShoppingListAddTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onAdd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .none
        field.font = AppTypography.bodyUIFont
        field.autocorrectionType = .default
        field.returnKeyType = .continue
        field.enablesReturnKeyAutomatically = true
        field.placeholder = Bundle.currentLocalizedString("shopping.add.placeholder")
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged),
            for: .editingChanged
        )
        field.accessibilityIdentifier = AccessibilityIdentifiers.shoppingAddField
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.placeholder = Bundle.currentLocalizedString("shopping.add.placeholder")
        if uiView.text != text {
            uiView.text = text
        }

        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard uiView.window != nil else { return }
                uiView.becomeFirstResponder()
            }
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ShoppingListAddTextField

        init(parent: ShoppingListAddTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onAdd()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }
    }
}

private extension View {
    /// Sort control as the first (scrolling) list row — no separator, transparent background,
    /// same horizontal inset as the rows below it.
    func sortControlRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: 8,
                leading: RecipeRowLayoutMetrics.listHorizontalInset,
                bottom: 8,
                trailing: RecipeRowLayoutMetrics.listHorizontalInset
            )
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// Same spacing as `RecipeListSectionHeader.recipeListSectionHeaderRow()` below the search slot.
    func shoppingSectionLabelRow() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: RecipeRowLayoutMetrics.listHorizontalInset,
                    bottom: 0,
                    trailing: RecipeRowLayoutMetrics.listHorizontalInset
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 1)
    }
}

// MARK: - Share sheet

private struct ShoppingListShareSheet: View {
    @Environment(YjsSyncService.self) private var syncService
    @Environment(\.dismiss) private var dismiss

    let isOnline: Bool
    @State private var shareEnabled = false
    @State private var publicId: String?
    @State private var settingsLoaded = false
    @State private var isUpdatingShare = false

    private var shareURL: URL? {
        guard let publicId else { return nil }
        return PublicURLBuilder.shoppingListShareURL(publicId: publicId)
    }

    private var sortMode: ShoppingSortMode {
        syncService.shoppingSnapshot.meta.sortMode
    }

    private var toBuy: [ShoppingListItem] {
        let items = syncService.shoppingSnapshot.items.filter { !$0.purchased }
        switch sortMode {
        case .recipe:
            return items.sorted { lhs, rhs in
                let ln = lhs.recipeName.isEmpty ? "~" : lhs.recipeName
                let rn = rhs.recipeName.isEmpty ? "~" : rhs.recipeName
                if ln != rn { return ln.localizedCompare(rn) == .orderedAscending }
                return lhs.label.localizedCompare(rhs.label) == .orderedAscending
            }
        case .alphabet:
            return items.sorted {
                ShoppingListFromRecipe.sortName(for: $0.label)
                    .localizedCompare(ShoppingListFromRecipe.sortName(for: $1.label)) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !isOnline {
                    Section {
                        Text("account.offline.alert")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle(isOn: shareToggleBinding) {
                        Text(String(localized: "shopping.public-link-title"))
                    }
                    .disabled(!isOnline || !settingsLoaded || isUpdatingShare)

                    if shareEnabled, let shareURL {
                        ShareLink(item: shareURL) {
                            Text(shareURL.absoluteString)
                                .appBody()
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tint(Color.accentColor)
                        Button(String(localized: "shopping.copy-link")) {
                            copyToPasteboard(shareURL.absoluteString)
                            postCopyFeedback(String(localized: "shopping.link-copied"))
                        }
                        .disabled(!isOnline)
                    }
                }

                Section {
                    Button(String(localized: "shopping.copy-as-text")) {
                        copyListAsText()
                    }
                    .disabled(toBuy.isEmpty)
                    .accessibilityIdentifier(AccessibilityIdentifiers.shoppingCopyAsTextButton)
                }
            }
            .appOpaqueGroupedListSurface()
            .localizedNavigationTitle("shopping.share-button")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadSettings()
                #if DEBUG
                if DebugLaunchOptions.shoppingShareAutoCopyText {
                    let deadline = Date().addingTimeInterval(20)
                    while toBuy.isEmpty, Date() < deadline {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                    guard !toBuy.isEmpty else { return }
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    copyListAsText()
                }
                #endif
            }
        }
        .appOpaqueSheetPresentation(detents: [.medium, .large])
    }

    private var shareToggleBinding: Binding<Bool> {
        Binding(
            get: { shareEnabled },
            set: { newValue in
                Task { await setShareEnabled(newValue) }
            }
        )
    }

    private func loadSettings() async {
        guard isOnline else {
            settingsLoaded = true
            return
        }
        if let data = try? await SharingAPI.fetchShoppingListSettings() {
            publicId = data.public_id
            shareEnabled = data.share_enabled
        }
        settingsLoaded = true
    }

    private func setShareEnabled(_ enabled: Bool) async {
        guard isOnline else {
            ShoppingFeedback.postStatus(String(localized: "account.offline.alert"))
            return
        }
        let previous = shareEnabled
        shareEnabled = enabled
        isUpdatingShare = true
        defer { isUpdatingShare = false }
        do {
            let data = try await SharingAPI.updateShoppingListShare(enabled: enabled)
            publicId = data.public_id
            shareEnabled = data.share_enabled
        } catch {
            shareEnabled = previous
            ShoppingFeedback.postStatus(String(localized: "shopping.share-update-error"))
        }
    }

    private func copyListAsText() {
        let text = ShoppingListPlainText.build(
            items: toBuy,
            headings: .init(
                misc: String(localized: "shopping.copy-text-misc"),
                untitledRecipe: String(localized: "shopping.copy-text-untitled-recipe")
            ),
            sortMode: sortMode
        )
        guard !text.isEmpty else { return }
        copyToPasteboard(text)
        postCopyFeedback(String(localized: "shopping.text-copied"))
    }

    private func postCopyFeedback(_ message: String) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            ShoppingFeedback.postStatus(message)
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}