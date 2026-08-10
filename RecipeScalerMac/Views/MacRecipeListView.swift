import SwiftUI
import AppKit
import RecipeScalerCore

/// macOS adapter for the shared Recipes data model.
///
/// The iOS list keeps its navigation-stack and swipe-action implementation.
/// macOS uses the same `YjsSyncService` mutations and collection index, but
/// renders native pointer affordances: swipe actions and context menu.
struct MacRecipeListView: View {
    @Environment(YjsSyncService.self) private var syncService
    @Binding var wideSelectedRecipeId: String?
    @Binding var activeFolderId: String?

    @AppStorage(RecipeFolderRoutes.viewModeStorageKey)
    private var viewModeRaw = RecipeFolderRoutes.ViewMode.collections.rawValue
    @State private var searchText = ""
    @State private var folderNavigationPath = NavigationPath()
    @State private var isCreatingRecipe = false
    @State private var errorMessage: String?
    @State private var assignmentEntry: CollectionEntry?
    @State private var pendingDeleteEntry: CollectionEntry?

    init(
        wideSelectedRecipeId: Binding<String?>,
        activeFolderId: Binding<String?>
    ) {
        _wideSelectedRecipeId = wideSelectedRecipeId
        _activeFolderId = activeFolderId
    }

    private var viewMode: RecipeFolderRoutes.ViewMode {
        RecipeFolderRoutes.ViewMode(rawValue: viewModeRaw) ?? .collections
    }

    private var isAtCollectionsRoot: Bool {
        folderNavigationPath.isEmpty
    }

    private var folders: [RecipeFolder] {
        RecipeFolder.sortedActive(syncService.folders)
    }

    var body: some View {
        NavigationStack(path: $folderNavigationPath) {
            rootContent
                .navigationDestination(for: String.self) { folderId in
                    folderRecipeList(folderId: folderId)
                        .onAppear {
                            activeFolderId = folderId
                        }
                }
        }
        .navigationTitle("")
        .searchable(text: $searchText, prompt: Text("search.recipes"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if isAtCollectionsRoot {
                    viewModePicker
                }
            }
            ToolbarItem {
                Button {
                    Task { await createRecipe() }
                } label: {
                    AppToolbarStyle.iconOnly(systemName: "plus")
                }
                .appToolbarIconButton()
                .disabled(isCreatingRecipe)
                .help(Text("recipes.add-button"))
                .accessibilityLabel(Text("recipes.add-button"))
                .accessibilityIdentifier(AccessibilityIdentifiers.recipeListAdd)
            }
        }
        .onAppear {
            restoreFolderRouteIfNeeded()
            syncNavigationPathFromActiveFolder()
        }
        .onChange(of: activeFolderId) { _, folderId in
            LayoutPreferencesStore.lastRecipesRoute = folderId.map { "/folder/\($0)" } ?? "/"
            if let folderId, !RecipeFolderRoutes.isValidFolderId(
                folderId,
                userFolderIds: folders.map(\.id)
            ) {
                activeFolderId = nil
                folderNavigationPath = NavigationPath()
                return
            }
            syncNavigationPathFromActiveFolder()
        }
        .onChange(of: folderNavigationPath.count) { _, count in
            if count == 0, activeFolderId != nil {
                activeFolderId = nil
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MacRecipeListWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(MacRecipeListWidthPreferenceKey.self) { width in
            guard width >= CGFloat(LayoutPreferencesStore.recipeListWidthMin) else { return }
            let roundedWidth = width.rounded()
            guard abs(LayoutPreferencesStore.recipeListWidth - Double(roundedWidth)) > 1 else {
                return
            }
            LayoutPreferencesStore.recipeListWidth = Double(roundedWidth)
        }
        .sheet(item: $assignmentEntry) { entry in
            MacCollectionAssignSheet(
                recipeId: entry.id,
                recipeName: RecipeTitleEmoji.displayName(for: entry.name)
            )
            .frame(minWidth: 360, minHeight: 320)
        }
        .alert(item: $pendingDeleteEntry) { entry in
            Alert(
                title: Text(String(localized: "recipe.list.delete.confirm.title")),
                message: Text(
                    String(
                        format: String(localized: "recipe.list.delete.confirm.message"),
                        locale: Locale.current,
                        RecipeTitleEmoji.displayName(for: entry.name)
                    )
                ),
                primaryButton: .destructive(
                    Text(String(localized: "recipe.list.delete.confirm.action"))
                ) {
                    delete(entry)
                },
                secondaryButton: .cancel(
                    Text(String(localized: "recipe.list.delete.confirm.cancel"))
                )
            )
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .appFootnote()
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            if isAtCollectionsRoot && viewMode == .collections && searchText.isEmpty {
                collectionsList
            } else if isAtCollectionsRoot {
                recipeList(entries: visibleEntries(for: nil))
            }
        }
    }

    private var collectionsList: some View {
        List {
            NavigationLink(value: CollectionVirtualFolders.allRecipesFolderId) {
                MacCollectionRowLabel(
                    title: String(localized: "collections.all-recipes"),
                    icon: "list.bullet",
                    count: syncService.collectionIndex.live.count
                )
            }
            .buttonStyle(.plain)
            .macStandardListRow()

            ForEach(folders) { folder in
                let count = syncService.collectionIndex.countByFolder[folder.id] ?? 0
                let presentation = FolderDisplayName.presentation(forStoredName: folder.name)
                NavigationLink(value: folder.id) {
                    MacCollectionRowLabel(
                        title: presentation.displayName,
                        leadingEmoji: presentation.leadingEmoji,
                        icon: RecipeFolderConstants.folderIconName(recipeCount: count),
                        count: count,
                        iconColor: RecipeAccentColor.color(from: folder.color)
                    )
                }
                .buttonStyle(.plain)
                .macStandardListRow()
            }

            let uncategorizedCount = syncService.collectionIndex.uncategorized.count
            if uncategorizedCount > 0 {
                NavigationLink(value: CollectionVirtualFolders.uncategorizedFolderId) {
                    MacCollectionRowLabel(
                        title: String(localized: "collections.uncategorized"),
                        icon: RecipeFolderConstants.folderIconName(recipeCount: uncategorizedCount),
                        count: uncategorizedCount
                    )
                }
                .buttonStyle(.plain)
                .macStandardListRow()
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.visible)
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeList)
    }

    private func folderRecipeList(folderId: String) -> some View {
        let presentation = folderPresentation(for: folderId)
        return recipeList(entries: visibleEntries(for: folderId))
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 6) {
                        if let leadingEmoji = presentation.leadingEmoji {
                            MacEmojiText(emoji: leadingEmoji, size: AppTypography.bodySize)
                        }
                        Text(presentation.displayName)
                            .appBody()
                            .lineLimit(1)
                    }
                }
            }
    }

    @ViewBuilder
    private func recipeList(entries: [CollectionEntry]) -> some View {
        if entries.isEmpty {
            ContentUnavailableView {
                AppEmptyState.label(
                    searchText.isEmpty ? "recipe.list.empty.title" : "recipe.list.search-empty.title",
                    symbol: searchText.isEmpty ? "book" : "magnifyingglass"
                )
            } description: {
                if searchText.isEmpty {
                    Text("recipe.list.empty.description")
                        .appBody()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(entries, id: \.id) { entry in
                    MacRecipeRow(
                        entry: entry,
                        isSelected: wideSelectedRecipeId == entry.id,
                        onSelect: { wideSelectedRecipeId = entry.id },
                        onPin: { togglePin(entry) },
                        onAddToShopping: { addToShopping(entry) },
                        onAssignToCollections: { assignmentEntry = entry },
                        onDelete: { pendingDeleteEntry = entry }
                    )
                    .macStandardListRow()
                    .listRowBackground(
                        wideSelectedRecipeId == entry.id
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeRow(id: entry.id))
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            addToShopping(entry)
                        } label: {
                            Label(
                                "shopping.detail-add-all",
                                systemImage: "cart.badge.plus"
                            )
                        }
                        .tint(.green)

                        Button {
                            assignmentEntry = entry
                        } label: {
                            Label(
                                "collections.assign-tooltip",
                                systemImage: "folder.badge.plus"
                            )
                        }
                        .tint(.orange)

                        Button {
                            togglePin(entry)
                        } label: {
                            Label(
                                entry.isPinned ? "recipe.list.unpin" : "recipe.list.pin",
                                systemImage: entry.isPinned ? "pin.slash" : "pin"
                            )
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteEntry = entry
                        } label: {
                            Label("recipe.list.delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.visible)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeList)
        }
    }

    private var viewModePicker: some View {
        Picker(selection: $viewModeRaw) {
            Label {
                Text("collections.view-collections")
            } icon: {
                Image(systemName: "folder")
            }
            .tag(RecipeFolderRoutes.ViewMode.collections.rawValue)
            .help(Text("collections.view-collections-tooltip"))
            .accessibilityLabel(Text("collections.view-collections"))

            Label {
                Text("collections.view-flat")
            } icon: {
                Image(systemName: "list.bullet")
            }
            .tag(RecipeFolderRoutes.ViewMode.flat.rawValue)
            .help(Text("collections.view-flat-tooltip"))
            .accessibilityLabel(Text("collections.view-flat"))
        } label: {
            Text("collections.title")
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .fixedSize()
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeListViewMode)
    }

    private func visibleEntries(for folderId: String?) -> [CollectionEntry] {
        let entries: [CollectionEntry]
        if let folderId {
            switch folderId {
            case CollectionVirtualFolders.allRecipesFolderId:
                entries = syncService.collectionIndex.live
            case CollectionVirtualFolders.uncategorizedFolderId:
                entries = syncService.collectionIndex.uncategorized
            default:
                entries = syncService.collectionIndex.folderRecipesById[folderId] ?? []
            }
        } else {
            entries = syncService.collectionIndex.live
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
        }
    }

    private func folderPresentation(for folderId: String) -> FolderDisplayNamePresentation {
        if folderId == CollectionVirtualFolders.allRecipesFolderId {
            return FolderDisplayNamePresentation(
                leadingEmoji: nil,
                displayName: String(localized: "collections.all-recipes")
            )
        }
        if folderId == CollectionVirtualFolders.uncategorizedFolderId {
            return FolderDisplayNamePresentation(
                leadingEmoji: nil,
                displayName: String(localized: "collections.uncategorized")
            )
        }
        guard let folder = syncService.folders.first(where: { $0.id == folderId }) else {
            return FolderDisplayNamePresentation(
                leadingEmoji: nil,
                displayName: String(localized: "collections.title")
            )
        }
        return FolderDisplayName.presentation(forStoredName: folder.name)
    }

    private func folderDisplayName(_ folderId: String) -> String {
        folderPresentation(for: folderId).displayName
    }

    private func restoreFolderRouteIfNeeded() {
        guard activeFolderId == nil else { return }
        let route = LayoutPreferencesStore.lastRecipesRoute
        guard route.hasPrefix("/folder/") else { return }
        let folderId = String(route.dropFirst("/folder/".count))
        guard RecipeFolderRoutes.isValidFolderId(folderId, userFolderIds: folders.map(\.id)) else {
            return
        }
        activeFolderId = folderId
    }

    private func syncNavigationPathFromActiveFolder() {
        guard let activeFolderId else {
            if !folderNavigationPath.isEmpty {
                folderNavigationPath = NavigationPath()
            }
            return
        }
        guard folderNavigationPath.isEmpty else { return }
        folderNavigationPath.append(activeFolderId)
    }

    private func createRecipe() async {
        guard !isCreatingRecipe else { return }
        isCreatingRecipe = true
        defer { isCreatingRecipe = false }
        do {
            let recipeId = try await syncService.createRecipe()
            if let activeFolderId, !CollectionVirtualFolders.isKnownVirtualFolderId(activeFolderId) {
                try await syncService.setRecipeFolders(recipeId: recipeId, folderIds: [activeFolderId])
            }
            wideSelectedRecipeId = recipeId
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func togglePin(_ entry: CollectionEntry) {
        Task {
            do {
                try await syncService.setRecipePinned(recipeId: entry.id, isPinned: !entry.isPinned)
            } catch {
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }

    private func addToShopping(_ entry: CollectionEntry) {
        Task {
            do {
                _ = try await syncService.addWholeRecipeToShoppingList(recipeId: entry.id)
            } catch {
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }

    private func delete(_ entry: CollectionEntry) {
        Task {
            do {
                try await syncService.deleteRecipeFromCollection(recipeId: entry.id)
                if wideSelectedRecipeId == entry.id {
                    wideSelectedRecipeId = nil
                }
            } catch {
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }
}

private enum MacListRowMetrics {
    static let height: CGFloat = 44
    static let markerSpacing: CGFloat = 6
    static let markerSlotSize: CGFloat = 22
    static let emojiSize: CGFloat = 18
    static let insets = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
}

private extension View {
    func macStandardListRow() -> some View {
        listRowInsets(MacListRowMetrics.insets)
            .frame(height: MacListRowMetrics.height)
    }
}

private struct MacRecipeListWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MacEmojiText: View {
    let emoji: String
    var size: CGFloat

    var body: some View {
        Text(emoji)
            .font(.system(size: size))
            .fixedSize()
    }
}

private struct MacRowMarkerSlot: View {
    let emoji: String?
    let color: String

    var body: some View {
        ZStack {
            if let emoji {
                MacEmojiText(emoji: emoji, size: MacListRowMetrics.emojiSize)
            } else {
                Circle()
                    .fill(RecipeAccentColor.color(from: color))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: MacListRowMetrics.markerSlotSize, height: MacListRowMetrics.markerSlotSize, alignment: .center)
    }
}

private struct MacCollectionMarkerSlot: View {
    let leadingEmoji: String?
    let icon: String
    var iconColor: Color = .accentColor

    var body: some View {
        Group {
            if let leadingEmoji {
                MacEmojiText(emoji: leadingEmoji, size: MacListRowMetrics.emojiSize)
            } else {
                Image(systemName: icon)
                    .font(.system(size: AppTypography.bodySize))
                    .foregroundStyle(iconColor)
            }
        }
        .frame(width: MacListRowMetrics.markerSlotSize, height: MacListRowMetrics.markerSlotSize, alignment: .center)
    }
}

private struct MacListRowTitleBlock: View {
    let title: String

    var body: some View {
        Text(title)
            .appBody()
            .lineLimit(1)
            .multilineTextAlignment(.leading)
    }
}

private struct MacCollectionRowLabel: View {
    let title: String
    var leadingEmoji: String? = nil
    let icon: String
    let count: Int
    var iconColor: Color = .accentColor

    var body: some View {
        HStack(spacing: MacListRowMetrics.markerSpacing) {
            MacCollectionMarkerSlot(
                leadingEmoji: leadingEmoji,
                icon: icon,
                iconColor: iconColor
            )
            MacListRowTitleBlock(title: title)
            Spacer(minLength: 0)
            Text("\(count)")
                .appFootnote()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct MacRecipeRow: View {
    let entry: CollectionEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onPin: () -> Void
    let onAddToShopping: () -> Void
    let onAssignToCollections: () -> Void
    let onDelete: () -> Void

    var body: some View {
        rowButton
            .contextMenu {
                Button {
                    onAssignToCollections()
                } label: {
                    Label("collections.assign-title", systemImage: "folder.badge.plus")
                }
                Button {
                    onPin()
                } label: {
                    Label(
                        entry.isPinned ? "recipe.list.unpin" : "recipe.list.pin",
                        systemImage: entry.isPinned ? "pin.slash" : "pin"
                    )
                }
                Button {
                    onAddToShopping()
                } label: {
                    Label("shopping.detail-add-all", systemImage: "cart.badge.plus")
                }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("recipe.list.delete", systemImage: "trash")
                }
            }
    }

    private var rowButton: some View {
        Button(action: onSelect) {
            HStack(spacing: MacListRowMetrics.markerSpacing) {
                MacRowMarkerSlot(
                    emoji: RecipeTitleEmoji.leadingEmoji(in: entry.name),
                    color: entry.color
                )
                MacListRowTitleBlock(title: RecipeTitleEmoji.displayName(for: entry.name))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(RecipeTitleEmoji.displayName(for: entry.name)))
        .accessibilityHint(Text("recipe.list.select-hint"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Native Mac version of the collection assignment sheet.
///
/// It deliberately shares the Yjs mutation contract with iOS while using a
/// regular Mac toolbar and pointer-friendly list instead of UIKit row metrics.
struct MacCollectionAssignSheet: View {
    let recipeId: String
    let recipeName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(YjsSyncService.self) private var syncService
    @State private var selectedFolderIds: Set<String> = []
    @State private var initialFolderIds: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var folders: [RecipeFolder] {
        RecipeFolder.sortedActive(syncService.folders)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(recipeName)
                        .appHeadline()
                }

                if folders.isEmpty {
                    ContentUnavailableView {
                        AppEmptyState.label("collections.assign-empty", symbol: "folder.badge.plus")
                    }
                } else {
                    ForEach(folders.indices, id: \.self) { index in
                        folderRow(folders[index])
                    }
                }
            }
            .navigationTitle(Text("collections.assign-title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("collections.done") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .alert(
                String(localized: "common.error"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("common.ok", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                loadCurrentMembership()
            }
            .onDisappear {
                Task { await persistMembershipIfNeeded() }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .accessibilityIdentifier("mac_collection_assign_sheet")
    }

    @ViewBuilder
    private func folderRow(_ folder: RecipeFolder) -> some View {
        let presentation = FolderDisplayName.presentation(forStoredName: folder.name)
        Button {
            toggle(folder.id)
        } label: {
            HStack(spacing: 10) {
                if let leadingEmoji = presentation.leadingEmoji {
                    MacEmojiText(emoji: leadingEmoji, size: AppTypography.bodySize)
                        .frame(width: 22, alignment: .center)
                }
                Text(presentation.displayName)
                    .appBody()
                    .foregroundStyle(.primary)
                Spacer()
                if selectedFolderIds.contains(folder.id) {
                    AppSymbol.image("checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadCurrentMembership() {
        guard let entry = syncService.collectionEntries.first(where: { $0.id == recipeId }) else {
            return
        }
        let ids = Set(entry.folderIds)
        selectedFolderIds = ids
        initialFolderIds = ids
    }

    private func toggle(_ folderId: String) {
        if selectedFolderIds.contains(folderId) {
            selectedFolderIds.remove(folderId)
        } else {
            selectedFolderIds.insert(folderId)
        }
    }

    private func persistMembershipIfNeeded() async {
        guard !isSaving, selectedFolderIds != initialFolderIds else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await syncService.setRecipeFolders(
                recipeId: recipeId,
                folderIds: Array(selectedFolderIds)
            )
            initialFolderIds = selectedFolderIds
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }
}
