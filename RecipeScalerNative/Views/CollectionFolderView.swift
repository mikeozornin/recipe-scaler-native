import SwiftUI

/// Drill-in view for a collection folder (virtual or user).
///
/// Shows the same pinned / unpinned recipe sections as the flat list,
/// plus an overflow menu for user folders (rename, select recipes, delete).
struct CollectionFolderView: View {
    let folderId: String

    @EnvironmentObject private var syncService: YjsSyncService
    @Binding var navigationPath: NavigationPath

    @State private var isEditingName = false
    @State private var editingName = ""
    @State private var editingColor = RecipeAccentColor.color(from: RecipeFolderConstants.defaultFolderColor)
    @State private var isNameFieldFocused = false
    @State private var showingDeleteConfirm = false
    @State private var showingManageRecipes = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var recipePendingDelete: RecipeRowData?
    @State private var isCreatingRecipe = false
    @State private var assignSheetRecipeId: String?
    @State private var assignSheetRecipeName: String?
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
        if isVirtual {
            if folderId == CollectionVirtualFolders.allRecipesFolderId {
                return Bundle.currentLocalizedString("collections.all-recipes")
            }
            return Bundle.currentLocalizedString("collections.uncategorized")
        }
        guard let folder = activeFolder else { return "" }
        return FolderDisplayName.displayName(forStoredName: folder.name)
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
        filteredEntries.filter(\.isPinned).map(RecipeRowData.init(entry:))
    }

    private var unpinnedRowItems: [RecipeRowData] {
        filteredEntries.filter { !$0.isPinned }.map(RecipeRowData.init(entry:))
    }

    private var hasAnyRows: Bool {
        !pinnedRowItems.isEmpty || !unpinnedRowItems.isEmpty
    }

    private var emptyStateFolderIconColor: Color {
        RecipeAccentColor.folderIconColor(folderId: folderId, folder: activeFolder)
    }

    var body: some View {
        Group {
            if folderRecipes.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(String(localized: "collections.empty-folder"))
                            .font(AppTypography.body)
                    } icon: {
                        Image(systemName: "folder")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(emptyStateFolderIconColor)
                    }
                }
                .mobileTimerPanelBottomPadding()
            } else if filteredEntries.isEmpty && isSearching {
                ContentUnavailableView.search(text: searchText)
                    .mobileTimerPanelBottomPadding()
            } else {
                List {
                    if !pinnedRowItems.isEmpty {
                        RecipeListSectionHeader(isPinnedSection: true)
                            .recipeListSectionHeaderRow()

                        recipeRows(pinnedRowItems)
                    }

                    if !unpinnedRowItems.isEmpty {
                        if !pinnedRowItems.isEmpty {
                            RecipeListSectionHeader(isPinnedSection: false)
                                .recipeListSectionHeaderRow()
                        }

                        recipeRows(unpinnedRowItems)
                    }

                    MobileTimerPanelListSpacerRow()
                }
                .listStyle(.plain)
                .listSectionSpacing(0)
                .environment(\.defaultMinListRowHeight, 1)
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
        .sheet(isPresented: $showingManageRecipes) {
            ManageCollectionRecipesSheet(folderId: folderId)
        }
        .sheet(item: Binding<CollectionAssignSheetItem?>(
            get: {
                guard let id = assignSheetRecipeId, let name = assignSheetRecipeName else { return nil }
                return CollectionAssignSheetItem(recipeId: id, recipeName: name)
            },
            set: { if $0 == nil { assignSheetRecipeId = nil; assignSheetRecipeName = nil } }
        )) { item in
            CollectionAssignSheet(recipeId: item.recipeId, recipeName: item.recipeName)
        }
        .alert("Error", isPresented: $showingError) {
            Button("common.ok", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert(
            String(localized: "recipe.list.delete.confirm.title"),
            isPresented: Binding(
                get: { recipePendingDelete != nil },
                set: { if !$0 { recipePendingDelete = nil } }
            ),
            presenting: recipePendingDelete
        ) { item in
            Button(String(localized: "recipe.list.delete.confirm.action"), role: .destructive) {
                Task { await confirmDeleteRecipe(item) }
            }
            Button(String(localized: "recipe.list.delete.confirm.cancel"), role: .cancel) {
                recipePendingDelete = nil
            }
        } message: { item in
            Text(
                String(
                    format: String(localized: "recipe.list.delete.confirm.message"),
                    locale: .current,
                    item.displayName
                )
            )
        }
        .alert(
            String(localized: "collections.delete-confirm-title"),
            isPresented: $showingDeleteConfirm
        ) {
            Button(String(localized: "collections.delete"), role: .destructive) {
                Task { await deleteFolder() }
            }
            Button(String(localized: "recipe.list.delete.confirm.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "collections.delete-confirm-description"))
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
                showingManageRecipes = true
            } label: {
                AppLabel.make(String(localized: "collections.select-recipes"), symbol: "folder.badge.plus")
            }

            Button(role: .destructive) {
                showingDeleteConfirm = true
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
                errorMessage = error.localizedDescription
                showingError = true
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
            errorMessage = error.localizedDescription
            showingError = true
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
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }

            navigationPath.append(
                RecipesRoute.recipe(
                    recipeId: recipeId,
                    folderContext: folderId,
                    openInEditMode: true
                )
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func togglePin(for item: RecipeRowData) async {
        do {
            try await syncService.setRecipePinned(recipeId: item.id, isPinned: !item.isPinned)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
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
            ShoppingFeedback.postStatus(error.localizedDescription)
        }
    }

    private func confirmDeleteRecipe(_ item: RecipeRowData) async {
        recipePendingDelete = nil
        do {
            try await syncService.deleteRecipeFromCollection(recipeId: item.id)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
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

    @ViewBuilder
    private func recipeRows(_ items: [RecipeRowData]) -> some View {
        ForEach(items) { item in
            ZStack(alignment: .leading) {
                RecipeRow(
                    data: item,
                    highlight: isSearching ? searchStore.highlights[item.id] : nil,
                    allowsNetworkRefresh: allowsImageNetworkRefresh
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                let route = RecipesRoute.recipe(
                    recipeId: item.id,
                    folderContext: RecipeFolderRoutes.shouldUseFolderRecipePath(
                        activeFolderId: folderId,
                        viewMode: .collections,
                        recipeFolderIds: syncService.collectionEntries
                            .first { $0.id == item.id }?.folderIds
                    ) ? folderId : nil
                )
                NavigationLink(value: route) {
                    Color.clear
                }
                .frame(maxWidth: .infinity, minHeight: RecipeRowLayoutMetrics.rowHeight)
                .opacity(0.01)
            }
            .buttonStyle(.plain)
            .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeRow(id: item.id))
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

                Button {
                    assignSheetRecipeId = item.id
                    assignSheetRecipeName = item.displayName
                } label: {
                    Label(
                        String(localized: "collections.assign-tooltip"),
                        systemImage: "folder.badge.plus"
                    )
                }
                .tint(.orange)

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
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    recipePendingDelete = item
                } label: {
                    AppLabel.make(String(localized: "recipe.list.delete"), symbol: "trash")
                }
                .tint(.red)
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

}

// MARK: - Navigation title modifier (supports inline rename)

private struct FolderNavigationTitleModifier: ViewModifier {
    let isEditingName: Bool
    @Binding var editingName: String
    @Binding var editingColor: Color
    let displayName: String
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

// MARK: - Assign sheet item (for .sheet(item:))

private struct CollectionAssignSheetItem: Identifiable {
    let recipeId: String
    let recipeName: String
    var id: String { recipeId }
}
