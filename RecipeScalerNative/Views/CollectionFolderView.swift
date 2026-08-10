import SwiftUI

/// Drill-in view for a collection folder (virtual or user).
///
/// Shows the same pinned / unpinned recipe sections as the flat list,
/// plus an overflow menu for user folders (rename, select recipes, delete).
struct CollectionFolderView: View {
    let folderId: String

    @Environment(YjsSyncService.self) private var syncService
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelIsCollapsed) private var mobileTimerPanelIsCollapsed
    @Binding var navigationPath: NavigationPath
    var onRecipeSelectionChanged: ((String?, String?) -> Void)? = nil
    var wideSelectedRecipeId: Binding<String?>? = nil

    @State private var isEditingName = false
    @State private var editingName = ""
    @State private var editingColor = RecipeAccentColor.color(from: RecipeFolderConstants.defaultFolderColor)
    @State private var isNameFieldFocused = false
    @State private var presentedSheet: CollectionFolderSheet?
    @State private var presentedAlert: CollectionFolderAlert?
    @State private var isCreatingRecipe = false
    @State private var searchText = ""
    /// Lazy recipe loader + highlight cache scoped to this folder.
    @State private var searchStore = RecipeListSearchStore()
    /// Tokens derived from `searchText` once per change.
    @State private var searchTokens: [String] = []

    private var isVirtual: Bool {
        CollectionVirtualFolders.isKnownVirtualFolderId(folderId)
    }

    private var activeFolder: RecipeFolder? {
        syncService.folders.first { $0.id == folderId }
    }

    private var displayName: String {
        folderPresentation.displayName
    }

    private var folderPresentation: FolderDisplayNamePresentation {
        if isVirtual {
            if folderId == CollectionVirtualFolders.allRecipesFolderId {
                return FolderDisplayNamePresentation(
                    leadingEmoji: nil,
                    displayName: Bundle.currentLocalizedString("collections.all-recipes")
                )
            }
            return FolderDisplayNamePresentation(
                leadingEmoji: nil,
                displayName: Bundle.currentLocalizedString("collections.uncategorized")
            )
        }
        guard let folder = activeFolder else {
            return FolderDisplayNamePresentation(leadingEmoji: nil, displayName: "")
        }
        return FolderDisplayName.presentation(forStoredName: folder.name)
    }

    /// Recipes for this folder, respecting the folder's membership rules.
    private var folderRecipes: [CollectionEntry] {
        let index = syncService.collectionIndex
        if folderId == CollectionVirtualFolders.allRecipesFolderId {
            return index.live
        }
        if folderId == CollectionVirtualFolders.uncategorizedFolderId {
            return index.uncategorized
        }
        return index.folderRecipesById[folderId] ?? []
    }

    private var isSearching: Bool {
        !searchTokens.isEmpty
    }

    /// Entries to render: precomputed filtered snapshot when searching, full
    /// folder list otherwise. Reads the store's single published snapshot.
    private var filteredEntries: [CollectionEntry] {
        if isSearching {
            return searchStore.filteredSnapshot
        }
        return folderRecipes
    }

    private var pinnedRowItems: [RecipeRowData] {
        pinPartitionedEntries.pinned.map(RecipeRowData.init(entry:))
    }

    private var unpinnedRowItems: [RecipeRowData] {
        pinPartitionedEntries.unpinned.map(RecipeRowData.init(entry:))
    }

    /// Folder lists and search snapshots are pin-first sorted; partition once.
    private var pinPartitionedEntries: (pinned: [CollectionEntry], unpinned: [CollectionEntry]) {
        CollectionRecipesIndex.partitionPinned(filteredEntries)
    }

    /// Stable signature of the PIN STATE only (which entries are pinned,
    /// ignoring all other fields like `updatedAt`).
    ///
    /// Used as the `.id()` of the `List` so SwiftUI rebuilds the list's view
    /// tree exactly when pin membership changes, bypassing iOS 26's built-in
    /// List structural-change animation (which cannot be disabled via
    /// `.animation(nil, value:)` or `.transaction { $0.animation = nil }`
    /// and produces the "jump over header / teleport / blink" artifacts).
    /// Server echoes that only bump `updatedAt` do not change this signature,
    /// so they no longer trigger a rebuild.
    private var pinStateSignature: String {
        pinnedRowItems.map(\.id).joined(separator: ",")
    }

    private var hasAnyRows: Bool {
        !pinnedRowItems.isEmpty || !unpinnedRowItems.isEmpty
    }

    var body: some View {
        Group {
            if folderRecipes.isEmpty {
                ContentUnavailableView {
                    VStack(spacing: 12) {
                        AppEmptyStateIllustration(asset: .recipeNotebookEmpty)
                        Text(String(localized: "collections.empty-folder"))
                            .font(AppTypography.body)
                    }
                }
                .mobileTimerPanelBottomPadding()
            } else if filteredEntries.isEmpty && isSearching {
                ContentUnavailableView {
                    AppEmptyState.label("recipe.list.search-empty.title", symbol: "magnifyingglass")
                }
                .font(AppTypography.body)
                .mobileTimerPanelBottomPadding()
            } else {
                List {
                    // Single ForEach across both pinned and unpinned rows so
                    // SwiftUI preserves row identity during pin/unpin.
                    recipeRowsWithHeaders

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
                // Force SwiftUI to rebuild the List's view tree whenever the
                // pin-state signature changes. iOS 26's List has a built-in
                // structural-change animation that cannot be disabled via
                // `.animation(nil, value:)` or `.transaction { $0.animation = nil }`
                // (both were tried and confirmed ineffective). Rebuilding
                // the tree via `.id()` skips the broken animation entirely,
                // giving an instant transition. This sacrifices SwiftUI's
                // move animation entirely, which is the goal: a clean
                // instant transition is preferable to a broken animated one.
                .id(pinStateSignature)
            }
        }
        .searchable(text: $searchText, prompt: Text("search.recipes"))
        .onAppear {
            searchStore.bind(syncService: syncService)
        }
        .onChange(of: searchText) { _, query in
            searchTokens = RecipeSearchUtils.tokenizeQuery(query)
            searchStore.refresh(entries: folderRecipes, query: query)
        }
        .onChange(of: folderRecipes.map(\.id)) { _, _ in
            guard isSearching else { return }
            searchStore.refresh(entries: folderRecipes, query: searchText)
        }
        .modifier(FolderNavigationTitleModifier(
            isEditingName: isEditingName,
            editingName: $editingName,
            editingColor: $editingColor,
            displayName: displayName,
            leadingEmoji: folderPresentation.leadingEmoji,
            isNameFieldFocused: $isNameFieldFocused,
            onCommit: commitRename,
            onCancel: cancelRename
        ))
        .appListBodyTypography()
        .toolbar {
            if !isEditingName {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        if !isVirtual {
                            folderMenu
                        }
                        createRecipeButton
                    }
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .assign(let recipeId, let recipeName):
                CollectionAssignSheet(recipeId: recipeId, recipeName: recipeName)
            case .manageRecipes:
                ManageCollectionRecipesSheet(folderId: folderId)
            }
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .error(let message):
                Alert(
                    title: Text(verbatim: Bundle.currentLocalizedString("common.error")),
                    message: Text(message),
                    dismissButton: .cancel(Text(verbatim: Bundle.currentLocalizedString("common.ok")))
                )
            case .deleteRecipe(let item):
                Alert(
                    title: Text(String(localized: "recipe.list.delete.confirm.title")),
                    message: Text(
                        String(
                            format: String(localized: "recipe.list.delete.confirm.message"),
                            locale: .current,
                            item.displayName
                        )
                    ),
                    primaryButton: .destructive(Text(String(localized: "recipe.list.delete.confirm.action"))) {
                        Task { await confirmDeleteRecipe(item) }
                    },
                    secondaryButton: .cancel(Text(String(localized: "recipe.list.delete.confirm.cancel")))
                )
            case .deleteFolder:
                Alert(
                    title: Text(String(localized: "collections.delete-confirm-title")),
                    message: Text(String(localized: "collections.delete-confirm-description")),
                    primaryButton: .destructive(Text(String(localized: "collections.delete"))) {
                        Task { await deleteFolder() }
                    },
                    secondaryButton: .cancel(Text(String(localized: "recipe.list.delete.confirm.cancel")))
                )
            }
        }
    }

    // MARK: - Folder menu

    @ViewBuilder
    private var folderMenu: some View {
        Menu {
            Button {
                startRename()
            } label: {
                AppLabel.make(String(localized: "collections.rename"), symbol: "pencil")
            }

            Button {
                presentedSheet = .manageRecipes
            } label: {
                AppLabel.make(String(localized: "collections.select-recipes"), symbol: "folder.badge.plus")
            }

            Button(role: .destructive) {
                presentedAlert = .deleteFolder
            } label: {
                AppLabel.make(String(localized: "collections.delete"), symbol: "trash")
            }
        } label: {
            AppToolbarStyle.iconOnly(systemName: "ellipsis")
        }
        .appToolbarIconButton()
    }

    @ViewBuilder
    private var createRecipeButton: some View {
        Button {
            Task { @MainActor in
                await handleCreateRecipe()
            }
        } label: {
            AppToolbarStyle.iconOnly(systemName: "plus")
        }
        .appToolbarIconButton()
        .disabled(isCreatingRecipe)
        .accessibilityLabel("recipes.add-button")
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeListAdd)
    }

    // MARK: - Inline rename

    private func startRename() {
        editingName = activeFolder?.name ?? ""
        editingColor = RecipeAccentColor.color(
            from: activeFolder?.color ?? RecipeFolderConstants.defaultFolderColor
        )
        isEditingName = true
        isNameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        isNameFieldFocused = false

        guard !trimmed.isEmpty else {
            isEditingName = false
            return
        }

        let baselineColor = RecipeAccentColor.normalizedStored(
            activeFolder?.color ?? RecipeFolderConstants.defaultFolderColor
        )
        let draftColor = RecipeAccentColor.storedValue(from: editingColor)
        let nameChanged = trimmed != (activeFolder?.name ?? "")
        let colorChanged = RecipeAccentColor.normalizedStored(draftColor) != baselineColor

        guard nameChanged || colorChanged else {
            isEditingName = false
            return
        }

        Task {
            do {
                if nameChanged {
                    try await syncService.renameFolder(id: folderId, name: trimmed)
                }
                if colorChanged {
                    try await syncService.updateFolderColor(id: folderId, color: draftColor)
                }
                isEditingName = false
            } catch {
                isEditingName = false
                presentedAlert = .error(UserFacingAPIError.message(for: error))
            }
        }
    }

    private func cancelRename() {
        isEditingName = false
        isNameFieldFocused = false
        editingName = ""
    }

    // MARK: - Actions

    private func deleteFolder() async {
        do {
            try await syncService.deleteFolder(id: folderId)
            navigationPath.removeLast()
        } catch {
            presentedAlert = .error(UserFacingAPIError.message(for: error))
        }
    }

    private func handleCreateRecipe() async {
        guard !isCreatingRecipe else { return }
        isCreatingRecipe = true
        defer { isCreatingRecipe = false }

        do {
            let recipeId = try await syncService.createRecipe()

            let shouldAssignFolder = activeFolder != nil && !isVirtual
            if shouldAssignFolder {
                do {
                    try await syncService.setRecipeFolders(recipeId: recipeId, folderIds: [folderId])
                } catch {
                    presentedAlert = .error(UserFacingAPIError.message(for: error))
                }
            }

            if let wideSelectedRecipeId {
                wideSelectedRecipeId.wrappedValue = recipeId
            } else {
                onRecipeSelectionChanged?(recipeId, folderId)
                navigationPath.append(
                    RecipesRoute.recipe(
                        recipeId: recipeId,
                        folderContext: folderId,
                        openInEditMode: true
                    )
                )
            }
        } catch {
            presentedAlert = .error(UserFacingAPIError.message(for: error))
        }
    }

    private func togglePin(for item: RecipeRowData) async {
        do {
            try await syncService.setRecipePinned(recipeId: item.id, isPinned: !item.isPinned)
        } catch {
            presentedAlert = .error(UserFacingAPIError.message(for: error))
        }
    }

    private func addRecipeToShopping(_ item: RecipeRowData) async {
        do {
            let added = try await syncService.addWholeRecipeToShoppingList(recipeId: item.id)
            if added > 0 {
                ShoppingFeedback.postStatus(ShoppingAddFeedback.message(for: added))
            } else {
                ShoppingFeedback.postStatus(String(localized: "shopping.no-items-to-add"))
            }
        } catch {
            ShoppingFeedback.postStatus(UserFacingAPIError.message(for: error))
        }
    }

    private func confirmDeleteRecipe(_ item: RecipeRowData) async {
        do {
            try await syncService.deleteRecipeFromCollection(recipeId: item.id)
        } catch {
            presentedAlert = .error(UserFacingAPIError.message(for: error))
        }
    }

    private var allowsImageNetworkRefresh: Bool {
        switch syncService.connectionState {
        case .connected:
            return true
        case .connecting, .reconnecting, .disconnected, .error:
            return false
        }
    }

    // MARK: - Recipe rows (same pattern as RecipeListView)

    /// Unified list item for the single-ForEach layout: either a section
    /// header (Pinned / All recipes) or a recipe row. Sharing one identity
    /// domain lets SwiftUI animate pin/unpin as a move within one collection
    /// rather than a delete+insert between two ForEachs. Section headers
    /// have their own stable ids and are part of the same ForEach.
    private enum ListItem: Identifiable, Equatable {
        case pinnedHeader
        case unpinnedHeader
        case recipe(RecipeRowData)

        var id: String {
            switch self {
            case .pinnedHeader: return "__section_pinned"
            case .unpinnedHeader: return "__section_unpinned"
            case .recipe(let row): return row.id
            }
        }
    }

    private var listItems: [ListItem] {
        var items: [ListItem] = []
        if !pinnedRowItems.isEmpty {
            items.append(.pinnedHeader)
            items.append(contentsOf: pinnedRowItems.map(ListItem.recipe))
        }
        if !unpinnedRowItems.isEmpty {
            if !pinnedRowItems.isEmpty {
                items.append(.unpinnedHeader)
            }
            items.append(contentsOf: unpinnedRowItems.map(ListItem.recipe))
        }
        return items
    }

    @ViewBuilder
    private var recipeRowsWithHeaders: some View {
        ForEach(listItems) { listItem in
            switch listItem {
            case .pinnedHeader:
                RecipeListSectionHeader(isPinnedSection: true)
                    .recipeListSectionHeaderRow()
            case .unpinnedHeader:
                RecipeListSectionHeader(isPinnedSection: false)
                    .recipeListSectionHeaderRow()
            case .recipe(let item):
                recipeRowView(for: item)
            }
        }
    }

    @ViewBuilder
    private func recipeRowView(for item: RecipeRowData) -> some View {
        let folderContext = RecipeFolderRoutes.shouldUseFolderRecipePath(
            activeFolderId: folderId,
            viewMode: .collections,
            recipeFolderIds: syncService.collectionEntries
                .first { $0.id == item.id }?.folderIds
        ) ? folderId : nil
        let route = RecipesRoute.recipe(
            recipeId: item.id,
            folderContext: folderContext
        )
        Group {
            if let wideSelectedRecipeId {
                RecipeRow(
                    data: item,
                    highlight: isSearching ? searchStore.highlights[item.id] : nil,
                    allowsNetworkRefresh: allowsImageNetworkRefresh
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    wideSelectedRecipeId.wrappedValue = item.id
                }
            } else {
                ZStack(alignment: .leading) {
                    RecipeRow(
                        data: item,
                        highlight: isSearching ? searchStore.highlights[item.id] : nil,
                        allowsNetworkRefresh: allowsImageNetworkRefresh
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    NavigationLink(value: route) {
                        Color.clear
                    }
                    .frame(maxWidth: .infinity, minHeight: RecipeRowLayoutMetrics.rowHeight)
                    .opacity(0.01)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            onRecipeSelectionChanged?(item.id, folderContext)
                        }
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeRow(id: item.id))
        .accessibilityAddTraits(
            wideSelectedRecipeId?.wrappedValue == item.id ? .isSelected : []
        )
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                Task { await addRecipeToShopping(item) }
            } label: {
                Label(
                    String(localized: "shopping.detail-add-all"),
                    systemImage: "cart.badge.plus"
                )
            }
            .tint(.green)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeRowShopping(id: item.id))

            Button {
                presentedSheet = .assign(recipeId: item.id, recipeName: item.displayName)
            } label: {
                Label(
                    String(localized: "collections.assign-tooltip"),
                    systemImage: "folder.badge.plus"
                )
            }
            .tint(.orange)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeRowAssign(id: item.id))

            Button {
                Task { await togglePin(for: item) }
            } label: {
                Label {
                    Text(
                        item.isPinned
                            ? String(localized: "recipe.list.unpin")
                            : String(localized: "recipe.list.pin")
                    )
            } icon: {
                    AppSymbol.image(item.isPinned ? "pin.slash" : "pin")
                }
            }
            .tint(.blue)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeRowPin(id: item.id))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                presentedAlert = .deleteRecipe(item)
            } label: {
                AppLabel.make(String(localized: "recipe.list.delete"), symbol: "trash")
            }
            .tint(.red)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeRowDelete(id: item.id))
        }
        .task(id: item.id) {
            guard item.hasThumbnail,
                  let fileURL = RecipeImageDiskCache.existingFileURL(recipeId: item.id, variant: .full) else {
                return
            }
            await Task.detached(priority: .utility) {
                _ = RecipeImageDisplayCache.image(fileURL: fileURL, variant: .full)
            }.value
        }
    }

}

// MARK: - Navigation title modifier (supports inline rename)

private struct FolderNavigationTitleModifier: ViewModifier {
    let isEditingName: Bool
    @Binding var editingName: String
    @Binding var editingColor: Color
    let displayName: String
    let leadingEmoji: String?
    @Binding var isNameFieldFocused: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isEditingName)
            .navigationTitle(Text(verbatim: isEditingName ? "" : displayName))
            .localizedNavigationBackTitle(verbatim: displayName)
            .toolbar {
                if isEditingName {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            RenameTextField(
                                text: $editingName,
                                isFocused: $isNameFieldFocused,
                                onSubmit: onCommit
                            )
                            .frame(maxWidth: .infinity)

                            ColorPicker(
                                String(localized: "collections.collection-color"),
                                selection: $editingColor,
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .frame(width: 30, height: 30)
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "recipe.list.delete.confirm.cancel")) {
                            onCancel()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "collections.done")) {
                            onCommit()
                        }
                    }
                } else if let leadingEmoji {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) {
                            Text(leadingEmoji)
                                .font(AppTypography.body)
                                .fixedSize()
                            Text(displayName)
                                .appBody()
                                .lineLimit(1)
                        }
                    }
                }
            }
    }
}

// MARK: - Rename text field (UITextField wrapper with focus & select-all)

private struct RenameTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .none
        field.textAlignment = .center
        field.returnKeyType = .done
        field.autocorrectionType = .no
        field.font = AppTypography.sansMediumBodyUIFont
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return field
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }

        if isFocused && !textField.isFirstResponder {
            DispatchQueue.main.async {
                guard textField.window != nil else { return }
                textField.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RenameTextField

        init(_ parent: RenameTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            textField.selectAll(nil)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }
    }
}

// MARK: - Modal presentation state

private enum CollectionFolderSheet: Identifiable {
    case assign(recipeId: String, recipeName: String)
    case manageRecipes

    var id: String {
        switch self {
        case .assign(let recipeId, _):
            "assign-\(recipeId)"
        case .manageRecipes:
            "manageRecipes"
        }
    }
}

private enum CollectionFolderAlert: Identifiable {
    case deleteRecipe(RecipeRowData)
    case deleteFolder
    case error(String)

    var id: String {
        switch self {
        case .deleteRecipe(let row):
            "delete-\(row.id)"
        case .deleteFolder:
            "deleteFolder"
        case .error(let message):
            "error-\(message.hashValue)"
        }
    }
}
