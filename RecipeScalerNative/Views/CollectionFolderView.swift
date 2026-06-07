import SwiftUI

/// Drill-in view for a collection folder (virtual or user).
///
/// Shows the same pinned / unpinned recipe sections as the flat list,
/// plus an overflow menu for user folders (rename, select recipes, delete).
struct CollectionFolderView: View {
    let folderId: String

    @EnvironmentObject private var syncService: YjsSyncService
    @Binding var navigationPath: NavigationPath

    @State private var searchText = ""
    @State private var isEditingName = false
    @State private var editingName = ""
    @State private var showingDeleteConfirm = false
    @State private var showingManageRecipes = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var recipePendingDelete: RecipeRowData?
    @State private var recipeIdToOpenInEditMode: String?
    @State private var assignSheetRecipeId: String?
    @State private var assignSheetRecipeName: String?

    @FocusState private var isNameFieldFocused: Bool

    private var isVirtual: Bool {
        CollectionVirtualFolders.isKnownVirtualFolderId(folderId)
    }

    private var activeFolder: RecipeFolder? {
        syncService.folders.first { $0.id == folderId }
    }

    private var displayName: String {
        if isVirtual {
            if folderId == CollectionVirtualFolders.allRecipesFolderId {
                return String(localized: "collections.all-recipes")
            }
            return String(localized: "collections.uncategorized")
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

    private var filteredEntries: [CollectionEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return folderRecipes }

        let tokens = tokenizeQuery(trimmed)
        return folderRecipes.filter { entry in
            tokens.allSatisfy { token in
                normalizeForSearch(entry.name).contains(token)
            }
        }
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

    var body: some View {
        Group {
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty && folderRecipes.isEmpty {
                ContentUnavailableView {
                    AppLabel.make(String(localized: "collections.empty-folder"), symbol: "folder")
                }
                .mobileTimerPanelBottomPadding()
            } else if !hasAnyRows && !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search
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
                .searchable(text: $searchText, prompt: String(localized: "search.recipes"))
            }
        }
        .modifier(FolderNavigationTitleModifier(
            isEditingName: isEditingName,
            editingName: $editingName,
            displayName: displayName,
            isNameFieldFocused: $isNameFieldFocused,
            onCommit: commitRename,
            onCancel: cancelRename
        ))
        .appListBodyTypography()
        .toolbar {
            if !isVirtual {
                ToolbarItem(placement: .topBarTrailing) {
                    folderMenu
                }
            }
        }
        .navigationDestination(for: RecipesRoute.self) { route in
            switch route {
            case .recipe(let recipeId, _):
                YDocRecipeDetailView(
                    recipeId: recipeId,
                    startInEditMode: recipeIdToOpenInEditMode == recipeId
                )
                .onAppear {
                    if recipeIdToOpenInEditMode == recipeId {
                        recipeIdToOpenInEditMode = nil
                    }
                }
            default:
                EmptyView()
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
            Button("OK", role: .cancel) { }
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
                AppLabel.make(String(localized: "collections.select-recipes"), symbol: "checklist")
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

    // MARK: - Inline rename

    private func startRename() {
        editingName = activeFolder?.name ?? ""
        isEditingName = true
        isNameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        isEditingName = false
        isNameFieldFocused = false

        guard !trimmed.isEmpty else { return }
        guard trimmed != (activeFolder?.name ?? "") else { return }

        Task {
            do {
                try await syncService.renameFolder(id: folderId, name: trimmed)
            } catch {
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
            if !navigationPath.isEmpty {
                navigationPath = NavigationPath()
            }
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
                    allowsNetworkRefresh: allowsImageNetworkRefresh
                )

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
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
                .tint(.orange)

                Button(role: .destructive) {
                    recipePendingDelete = item
                } label: {
                    AppLabel.make(String(localized: "recipe.list.delete"), symbol: "trash")
                }
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

    // MARK: - Search helpers

    private func tokenizeQuery(_ query: String) -> [String] {
        var tokens: [String] = []
        var remaining = query[...]

        while !remaining.isEmpty {
            remaining = Substring(remaining.trimmingCharacters(in: .whitespaces))
            if remaining.isEmpty { break }

            if remaining.hasPrefix("\"") {
                remaining = remaining.dropFirst()
                if let end = remaining.range(of: "\"") {
                    let phrase = String(remaining[..<end.lowerBound])
                    if !phrase.isEmpty {
                        tokens.append(normalizeForSearch(phrase))
                    }
                    remaining = remaining[end.upperBound...]
                } else {
                    tokens.append(normalizeForSearch(String(remaining)))
                    break
                }
            } else {
                if let space = remaining.range(of: " ") {
                    let word = String(remaining[..<space.lowerBound])
                    tokens.append(normalizeForSearch(word))
                    remaining = remaining[space.upperBound...]
                } else {
                    tokens.append(normalizeForSearch(String(remaining)))
                    break
                }
            }
        }

        return tokens
    }

    private func normalizeForSearch(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespaces)
            .decomposedStringWithCanonicalMapping
            .components(separatedBy: CharacterSet(charactersIn: "\u{0300}"..."\u{036F}"))
            .joined()
            .lowercased()
    }
}

// MARK: - Navigation title modifier (supports inline rename)

private struct FolderNavigationTitleModifier: ViewModifier {
    let isEditingName: Bool
    @Binding var editingName: String
    let displayName: String
    var isNameFieldFocused: FocusState<Bool>.Binding
    let onCommit: () -> Void
    let onCancel: () -> Void

    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        _ = locale
        if isEditingName {
            content.navigationTitle {
                TextField("", text: $editingName)
                    .focused(isNameFieldFocused)
                    .onSubmit { onCommit() }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "recipe.list.delete.confirm.cancel")) {
                                onCancel()
                            }
                        }
                    }
            }
        } else {
            content.navigationTitle(Text(verbatim: displayName))
        }
    }
}

// MARK: - Assign sheet item (for .sheet(item:))

private struct CollectionAssignSheetItem: Identifiable {
    let recipeId: String
    let recipeName: String
    var id: String { recipeId }
}
