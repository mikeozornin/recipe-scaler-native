//
//  ShoppingListView.swift
//  RecipeScalerNative
//

import SwiftUI

enum ToBuyPurchasePhase: Equatable {
    case staging
    case exiting
}

private enum ShoppingPurchaseTiming {
    static let stageSeconds: TimeInterval = 1.0
    static let exitSeconds: TimeInterval = 0.4
}

enum VkusvillUIVisibility {
    static func showsBuyButton(enabled: Bool, localeIdentifier: String?) -> Bool {
        guard let localeIdentifier else { return false }
        return enabled && localeIdentifier.lowercased().hasPrefix("ru")
    }
}

struct ShoppingListView: View {
    /// Injected (not `@Environment`): sibling tabs remasure nav chrome after
    /// assistant dismiss on iOS 26; `@Environment(SomeObservable.self)` traps
    /// in the fallback environment (same rule as RecipeListView).
    let syncService: YjsSyncService
    let timerManager: TimerManager
    let coordinator: AppShellCoordinator
    let authService: AuthService
    let vkusvillSettings: VkusvillSettingsStore
    let mobileTimerPanelIsCollapsed: Bool
    /// Spec 081 — ✦ in the toolbar: the iPad sidebar is shown, so the pinned «Ассистент»
    /// tab is not (`IPadLayoutPolicy.showsAssistantToolbarButton`, decided by the shell).
    let showsAssistantToolbarButton: Bool
    @Environment(\.locale) private var locale
    @Environment(\.appLayoutMode) private var layoutMode
    @Binding var path: NavigationPath
    /// Page frame in window coordinates (spec 081): «Купить во Вкусвилле» drops its text
    /// below 640 pt, and `minX` tells a side-by-side sidebar from an overlay one.
    @State private var pageFrame: CGRect = .zero
    /// Spec 081 — the iPad sidebar is on screen; otherwise the top tab bar shares the row
    /// with the toolbar.
    @State private var iPadSidebarShown = false
    @State private var bottomDraft = ""
    @State private var inlineEditItemId: String?
    @State private var inlineEditDraft = ""
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var purchasePhases: [String: ToBuyPurchasePhase] = [:]
    @State private var shoppingModel = ShoppingViewModel()
    @State private var showRemindersTip = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case bottom
        case inline(String)
    }

    init(
        path: Binding<NavigationPath>,
        syncService: YjsSyncService,
        timerManager: TimerManager,
        coordinator: AppShellCoordinator,
        authService: AuthService,
        vkusvillSettings: VkusvillSettingsStore,
        mobileTimerPanelIsCollapsed: Bool = true,
        showsAssistantToolbarButton: Bool = false
    ) {
        _path = path
        self.syncService = syncService
        self.timerManager = timerManager
        self.coordinator = coordinator
        self.authService = authService
        self.vkusvillSettings = vkusvillSettings
        self.mobileTimerPanelIsCollapsed = mobileTimerPanelIsCollapsed
        self.showsAssistantToolbarButton = showsAssistantToolbarButton
    }

    private var snapshot: ShoppingListSnapshot {
        syncService.shoppingSnapshot
    }

    private var isOnline: Bool {
        syncService.connectionState == .connected
    }

    private var showsVkusvillBuyButton: Bool {
        VkusvillUIVisibility.showsBuyButton(
            enabled: vkusvillSettings.enabled,
            localeIdentifier: locale.language.languageCode?.identifier
        )
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

    /// Spec 081, `.padRegular` only (the phone keeps the label): the page is narrower than
    /// 640 pt, or the toolbar row is shared — with the top tab bar, or under the overlay
    /// sidebar (the page does not move). The labeled button pushes the toolbar into the
    /// «…» overflow there (iPadOS 26.3, portrait).
    private var vkusvillIconOnly: Bool {
        guard layoutMode == .padRegular else { return false }
        let narrowPage = pageFrame.width > 0
            && pageFrame.width < IPadLayoutMetrics.shopLabeledMinContent
        let sidebarBesidePage = iPadSidebarShown && pageFrame.minX > 0
        return narrowPage || !sidebarBesidePage
    }

    private var shoppingListScreen: some View {
        ShoppingListToolbarHost(
            showsVkusvillBuyButton: showsVkusvillBuyButton,
            vkusvillIconOnly: vkusvillIconOnly,
            isOnline: isOnline,
            assistantCoordinator: showsAssistantToolbarButton ? coordinator : nil,
            onBuy: {
                coordinator.openAssistantWithMessage(
                    Bundle.currentLocalizedString("vkusvill.assistant-prompt")
                )
            },
            onShare: { showShareSheet = true }
        ) {
            shoppingList
                .iPadReadableWidth(IPadLayoutMetrics.readablePageWidth)
                .modifier(ShoppingIPadPageReader(pageFrame: $pageFrame, sidebarShown: $iPadSidebarShown))
        }
        .localizedNavigationTitle("shopping.title")
        .navigationBarTitleDisplayMode(.large)
        .appListBodyTypography()
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
                .environment(shoppingModel)
        }
        .errorAlert(message: $errorMessage)
        .task {
            refreshRemindersTipVisibility()
            await vkusvillSettings.refresh(
                userId: authService.userId,
                isOnline: isOnline
            )
        }
        .onAppear {
            seedShoppingModel()
            refreshRemindersTipVisibility()
        }
        .onChange(of: snapshot) { _, newValue in
            shoppingModel.recompute(snapshot: newValue, purchasePhases: purchasePhases)
        }
        .onChange(of: purchasePhases) { _, newValue in
            shoppingModel.recompute(snapshot: snapshot, purchasePhases: newValue)
        }
        .onChange(of: isOnline) { _, online in
            Task { @MainActor in
                await vkusvillSettings.refresh(
                    userId: authService.userId,
                    isOnline: online
                )
            }
        }
        .onChange(of: authService.userId) { _, userId in
            Task { @MainActor in
                await vkusvillSettings.refresh(
                    userId: userId,
                    isOnline: isOnline
                )
            }
        }
    }

    private var shoppingList: some View {
        List {
            if showRemindersTip {
                Section {
                    ShoppingRemindersTipBanner(
                        onEnable: {
                            ShoppingRemindersTipPreferences.dismiss()
                            showRemindersTip = false
                            coordinator.requestRemindersSetup()
                        },
                        onDismiss: {
                            ShoppingRemindersTipPreferences.dismiss()
                            showRemindersTip = false
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                shoppingSortControl
                    .sortControlRow()
            }

            if toBuy.isEmpty {
                // Not seeded yet → buckets are a placeholder; don't flash "basket empty".
                if shoppingModel.isSeeded {
                    emptyToBuyRow
                }
            } else if shoppingModel.toBuyGroups.isEmpty {
                Section {
                    AppSectionHeader("shopping.section.to-buy")
                        .shoppingSectionLabelRow()
                    ForEach(toBuy) { item in
                        toBuyRow(item, showsRecipeSubtitle: true)
                    }
                    .onDelete(perform: deleteToBuy)
                    addItemRow
                        .shoppingListItemRowInsets()
                }
            } else {
                toBuyRecipeSections
            }

            if !purchased.isEmpty {
                Section {
                    purchasedSectionHeader
                        .shoppingSectionLabelRow()
                    ForEach(purchased) { item in
                        shoppingRow(item, allowsInlineEdit: false, purchasePhase: nil, showsRecipeSubtitle: true)
                            .shoppingListItemRowInsets()
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
        .environment(\.defaultMinListRowHeight, 1)
        .animation(.easeInOut(duration: ShoppingPurchaseTiming.exitSeconds), value: purchasePhases)
        .animation(.easeInOut(duration: ShoppingPurchaseTiming.exitSeconds), value: shoppingModel.sortedToBuy)
        .animation(.easeInOut(duration: ShoppingPurchaseTiming.exitSeconds), value: shoppingModel.sortedPurchased)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    /// Recipe mode: one section per recipe titled with its name (rows drop the
    /// recipe subtitle), manual items last. The add field always lives in the
    /// manual section so a new item appears where it was typed.
    @ViewBuilder
    private var toBuyRecipeSections: some View {
        let groups = shoppingModel.toBuyGroups
        let miscTitle: LocalizedStringKey = groups.contains(where: { !$0.isMisc })
            ? "shopping.copy-text-misc"
            : "shopping.section.to-buy"
        ForEach(groups) { group in
            Section {
                Group {
                    if let recipeTitle = group.recipeTitle {
                        if recipeTitle.isEmpty {
                            AppSectionHeader("shopping.copy-text-untitled-recipe")
                        } else {
                            AppSectionHeader(verbatim: recipeTitle)
                        }
                    } else {
                        AppSectionHeader(miscTitle)
                    }
                }
                .shoppingSectionLabelRow()
                ForEach(group.items) { item in
                    toBuyRow(item, showsRecipeSubtitle: false)
                }
                .onDelete { offsets in
                    delete(items: group.items, at: offsets)
                }
                if group.isMisc {
                    addItemRow
                        .shoppingListItemRowInsets()
                }
            }
        }
        if !groups.contains(where: \.isMisc) {
            Section {
                AppSectionHeader(miscTitle)
                    .shoppingSectionLabelRow()
                addItemRow
                    .shoppingListItemRowInsets()
            }
        }
    }

    private var shoppingSortControl: some View {
        Picker("shopping.sort", selection: sortBinding) {
            Text("shopping.sort.by-recipe").tag(ShoppingSortMode.recipe)
            Text("shopping.sort.az").tag(ShoppingSortMode.alphabet)
        }
        .pickerStyle(.segmented)
    }

    /// Fills the buckets synchronously on appear (before the first frame) and
    /// without animation. The snapshot is already in memory (`YjsSyncService`
    /// loads it at launch); seeding it from `.task` showed the empty state for
    /// a frame and then ran the 0.4 s list animation (`[] → items`), which
    /// looked like a ~0.5 s load on every first open of the tab.
    private func seedShoppingModel() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            shoppingModel.recompute(snapshot: snapshot, purchasePhases: purchasePhases)
        }
    }

    private func refreshRemindersTipVisibility() {
        showRemindersTip = ShoppingRemindersTipPreferences.shouldShow
            && !RemindersSyncPreferences.isEnabled
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

    private var emptyToBuyRow: some View {
        Section {
            AppSectionHeader("shopping.section.to-buy")
                .shoppingSectionLabelRow()
            VStack(spacing: 12) {
                AppEmptyStateIllustration(
                    asset: purchased.isEmpty ? .shoppingBasketEmpty : .shoppingBasketFull,
                    // Compact when Reminders tip sits above — otherwise add-item is clipped by the tab bar.
                    size: showRemindersTip ? 156 : AppTypography.emptyStateIllustrationSize
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
            .frame(
                maxWidth: .infinity,
                minHeight: showRemindersTip ? 236 : 348,
                alignment: .center
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            addItemRow
                .shoppingListItemRowInsets()
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func toBuyRow(_ item: ShoppingListItem, showsRecipeSubtitle: Bool) -> some View {
        let phase = purchasePhases[item.id]
        Group {
            if inlineEditItemId == item.id, isManualItem(item) {
                inlineEditRow(item)
            } else {
                shoppingRow(item, allowsInlineEdit: true, purchasePhase: phase, showsRecipeSubtitle: showsRecipeSubtitle)
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
        .allowsHitTesting(phase != .exiting)
        .shoppingListItemRowInsets()
    }

    private func inlineEditRow(_ item: ShoppingListItem) -> some View {
        HStack(alignment: .center, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            shoppingRowMarker(systemName: "circle", foreground: .secondary)
            IngredientIllustrationSlot(
                content: .thumb(
                    illustrationId: ResolveShoppingIllustrationId.resolve(item: item),
                    isInteractive: false,
                    onTap: nil
                )
            )
            TextField(Bundle.currentLocalizedString("shopping.add.placeholder"), text: $inlineEditDraft)
                .font(AppTypography.body)
                .frame(height: RecipeRowLayoutMetrics.titleLineHeight)
                .focused($focusedField, equals: .inline(item.id))
                .submitLabel(.done)
                .onSubmit { commitInlineEdit(itemId: item.id) }
        }
        .ingredientListRowChrome()
        .onChange(of: focusedField) { _, newValue in
            if newValue != .inline(item.id) {
                commitInlineEdit(itemId: item.id)
            }
        }
    }

    private var addItemRow: some View {
        HStack(alignment: .center, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            shoppingRowMarker(systemName: "plus", foreground: .secondary)
            TextField(Bundle.currentLocalizedString("shopping.add.placeholder"), text: $bottomDraft)
                .font(AppTypography.body)
                .frame(height: RecipeRowLayoutMetrics.titleLineHeight)
                .focused($focusedField, equals: .bottom)
                .submitLabel(.done)
                .onSubmit { commitBottomDraft() }
                .accessibilityIdentifier(AccessibilityIdentifiers.shoppingAddField)
        }
        .ingredientListRowChrome()
        .onChange(of: focusedField) { _, newValue in
            if newValue != .bottom {
                commitBottomDraft()
            }
        }
    }

    @ViewBuilder
    private func shoppingRow(
        _ item: ShoppingListItem,
        allowsInlineEdit: Bool,
        purchasePhase: ToBuyPurchasePhase?,
        showsRecipeSubtitle: Bool
    ) -> some View {
        let showChecked = item.purchased || purchasePhase == .staging || purchasePhase == .exiting
        let hasRecipeSubtitle = showsRecipeSubtitle && !item.recipeName.isEmpty
        HStack(alignment: hasRecipeSubtitle ? .top : .center, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            Button {
                handlePurchaseToggle(item: item, phase: purchasePhase)
            } label: {
                shoppingRowMarker(
                    systemName: showChecked ? "checkmark.circle" : "circle",
                    foreground: Color.primary.opacity(showChecked ? 0.5 : 1)
                )
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(purchasePhase == .exiting)
            .accessibilityLabel(
                showChecked
                    ? String(localized: "shopping.mark-not-purchased")
                    : String(localized: "shopping.mark-purchased")
            )

            IngredientIllustrationSlot(
                content: .thumb(
                    illustrationId: ResolveShoppingIllustrationId.resolve(item: item),
                    isInteractive: false,
                    onTap: nil
                )
            )
            .opacity(showChecked ? 0.8 : 1)

            VStack(alignment: .leading, spacing: RecipeRowLayoutMetrics.searchSnippetSpacing) {
                Text(ShoppingListFromRecipe.displayLabel(for: item.label))
                    .appBody()
                    .strikethrough(showChecked)
                if hasRecipeSubtitle {
                    Text(item.recipeName)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(showChecked ? 0.5 : 1)
        }
        .ingredientListRowChrome()
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                handlePurchaseToggle(item: item, phase: purchasePhase)
            } label: {
                Label(
                    showChecked
                        ? String(localized: "shopping.mark-not-purchased")
                        : String(localized: "shopping.mark-purchased"),
                    systemImage: showChecked ? "circle" : "checkmark.circle"
                )
            }
            .tint(.green)
        }
    }

    /// Leading control rasterized at body size so UIImage-backed symbols don't inflate the row.
    private func shoppingRowMarker(systemName: String, foreground: some ShapeStyle) -> some View {
        AppSymbol.sizedImage(systemName, pointSize: RecipeRowLayoutMetrics.titleFontSize, weight: .semibold)
            .foregroundStyle(foreground)
            .frame(
                width: RecipeRowLayoutMetrics.titleLineHeight,
                height: RecipeRowLayoutMetrics.titleLineHeight,
                alignment: .center
            )
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
            ShoppingPurchaseHaptics.selection.selectionChanged()
        } else {
            ShoppingPurchaseHaptics.lightImpact.impactOccurred()
            ShoppingPurchaseHaptics.notification.notificationOccurred(.success)
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

    private func commitBottomDraft() {
        let text = bottomDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        bottomDraft = ""
        guard !text.isEmpty else { return }
        Task { await runShoppingMutation { try await syncService.addManualShoppingItem(label: text) } }
    }

    private func commitInlineEdit(itemId: String) {
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

    /// Section label above shopping rows. Bottom inset keeps the title off the white list block
    /// (plain `List` does not add UITableView-style header↔content gap on its own).
    func shoppingSectionLabelRow() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: RecipeRowLayoutMetrics.listHorizontalInset,
                    bottom: 8,
                    trailing: RecipeRowLayoutMetrics.listHorizontalInset
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 1)
    }

    /// Match recipe-list row box model: zero vertical insets; chrome supplies the 44 pt height.
    func shoppingListItemRowInsets() -> some View {
        listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
    }
}

// MARK: - Reminders tip

private struct ShoppingRemindersTipBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let onEnable: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("shopping.reminders-tip.message")
                    .appBody()
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onDismiss) {
                    AppSymbol.image("xmark")
                        .font(AppTypography.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Bundle.currentLocalizedString("common.close"))
                .accessibilityIdentifier(AccessibilityIdentifiers.shoppingRemindersTipDismiss)
            }

            Button(action: onEnable) {
                Text("shopping.reminders-tip.enable")
                    .appBody()
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityIdentifiers.shoppingRemindersTipEnable)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color.clear : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: colorScheme == .dark ? 0 : 10))
        .accessibilityIdentifier(AccessibilityIdentifiers.shoppingRemindersTip)
    }
}

// MARK: - Share sheet


/// Spec 081 — the page background, frame and sidebar placement behind `vkusvillIconOnly`,
/// iPad only. Nothing on the iPhone reads them (`vkusvillIconOnly` is `.padRegular` only),
/// so the phone list keeps the view tree it had before the iPad shell.
private struct ShoppingIPadPageReader: ViewModifier {
    @Binding var pageFrame: CGRect
    @Binding var sidebarShown: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        // Keyed on the idiom, which never changes while the app runs (as `iPadReadableWidth`),
        // so a compact iPad window keeps the same view tree.
        if UIDevice.current.userInterfaceIdiom == .pad {
            content
                // The margins around the 720 pt page share the list background.
                .background(Color(.systemGroupedBackground))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pageFrame = $0 }
                .reportsIPadSidebarShown($sidebarShown)
        } else {
            content
        }
    }
}

/// Toolbar host with no `@Environment(Observable.self)` — required so iOS 26
/// bar remasure after assistant dismiss does not trap in fallback env.
private struct ShoppingListToolbarHost<Content: View>: View {
    let showsVkusvillBuyButton: Bool
    /// Spec 081 — `.padRegular` page narrower than 640 pt.
    let vkusvillIconOnly: Bool
    let isOnline: Bool
    /// Spec 081 — ✦ on `.padRegular`; `nil` on the phone.
    let assistantCoordinator: AppShellCoordinator?
    let onBuy: () -> Void
    let onShare: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        if showsVkusvillBuyButton {
                            Button(action: onBuy) {
                                if vkusvillIconOnly {
                                    AppToolbarStyle.iconOnly(systemName: "banknote")
                                } else {
                                    AppToolbarStyle.labeledIcon(
                                        systemName: "banknote",
                                        title: "vkusvill.buy-button"
                                    )
                                }
                            }
                            .appToolbarIconButton()
                            .disabled(!isOnline)
                            .accessibilityIdentifier(AccessibilityIdentifiers.vkusvillBuyButton)
                            .accessibilityLabel(Text("vkusvill.buy-button"))
                            .accessibilityHint(
                                isOnline ? Text("") : Text("vkusvill.offline")
                            )
                        }
                        Button(action: onShare) {
                            AppToolbarStyle.iconOnly(systemName: "square.and.arrow.up")
                        }
                        .appToolbarIconButton()
                        .accessibilityLabel(Text("shopping.share-button"))
                        .accessibilityIdentifier(AccessibilityIdentifiers.shoppingShareButton)
                    }
                }
                if let assistantCoordinator {
                    ToolbarItem(placement: .topBarTrailing) {
                        IPadAssistantToolbarButton(coordinator: assistantCoordinator, startsNewChat: true)
                    }
                }
            }
    }
}

private struct ShoppingListShareSheet: View {
    @Environment(YjsSyncService.self) private var syncService
    @Environment(ShoppingViewModel.self) private var shoppingModel
    @Environment(OfflineBannerGate.self) private var offlineGate
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
        shoppingModel.sortedToBuy
    }

    var body: some View {
        NavigationStack {
            List {
                // Status banner gated by OfflineBannerGate (spec 066) — 3s debounce.
                // `isOnline` below (disabled buttons) intentionally stays instant.
                if offlineGate.isVisible {
                    Section {
                        Text("account.offline.alert")
                            .appBody()
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
        AppPasteboard.setString(text)
        #endif
    }
}

#if os(iOS)
/// Feedback generators for the purchase toggle, created once instead of on every tap.
@MainActor
private enum ShoppingPurchaseHaptics {
    static let selection = UISelectionFeedbackGenerator()
    static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    static let notification = UINotificationFeedbackGenerator()
}
#endif
