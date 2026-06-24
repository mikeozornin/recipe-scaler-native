import SwiftUI
import UIKit

struct RecipeListView: View {
    @Environment(YjsSyncService.self) private var syncService
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelIsCollapsed) private var mobileTimerPanelIsCollapsed
    @Binding var navigationPath: NavigationPath
    @State private var searchText = ""
    @State private var presentedSheet: RecipeListSheet?
    @State private var presentedAlert: RecipeListAlert?
    @State private var isCreatingRecipe = false
    /// Lazy recipe loader + highlight cache for full-text search.
    @State private var searchStore = RecipeListSearchStore()
    /// Tokens derived from `searchText` once per change, not per render.
    @State private var searchTokens: [String] = []
    /// Namespace for the iOS 26+ recipe list → detail zoom-morph transition.
    /// Pre-iOS 26 is unused (modifiers are no-ops). Shared between row anchors
    /// (`.recipeZoomTransitionSource`) and the detail destination
    /// (`.recipeZoomTransitionDestination`).
    @Namespace private var recipeZoomNamespace

    /// Persisted view mode: `nil` = default (collections).
    @AppStorage(RecipeFolderRoutes.viewModeStorageKey)
    private var viewModeRaw: String = RecipeFolderRoutes.ViewMode.collections.rawValue

    private var viewMode: RecipeFolderRoutes.ViewMode {
        RecipeFolderRoutes.ViewMode(rawValue: viewModeRaw) ?? .collections
    }

    init(navigationPath: Binding<NavigationPath> = .constant(NavigationPath())) {
        _navigationPath = navigationPath
    }
    #if DEBUG
    @State private var didOpenDebugRecipe = false
    #endif

    /// True under XCTest / UI-test hosts. The list view uses it to skip the
    /// cold-start loading spinner, which would otherwise spin forever because
    /// `AppContainer.bootstrap` short-circuits sync startup in those hosts.
    private var isUITestingHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("ui-testing")
    }

    private var isSearching: Bool {
        !searchTokens.isEmpty
    }

    /// Entries to render: precomputed filtered snapshot when searching, the
    /// full sorted list otherwise. Reads the live `@Observable` snapshot from
    /// `syncService.collectionEntries` directly so any field-level change
    /// (name/color/image/pin/folder) invalidates `body` — no manual cache.
    private var filteredEntries: [CollectionEntry] {
        if isSearching {
            return searchStore.filteredSnapshot
        }
        return RecipeTitleEmoji.sortCollectionEntries(syncService.collectionEntries)
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

    /// Whether we should show the collections root instead of the flat list.
    private var showsCollectionsRoot: Bool {
        viewMode == .collections && !isSearching
    }

    private var showsDatabaseInitFailedBanner: Bool {
        // Under XCTest/UI-test hosts the in-memory DB fallback is expected and
        // not actionable — the banner only confuses screenshot tests. Hide it
        // for those hosts; production users still see the real failure.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("ui-testing") {
            return false
        }
        return YrsDatabase.dbInitFailed
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if showsDatabaseInitFailedBanner {
                    DatabaseInitFailedBanner()
                }

                Group {
                if showsCollectionsRoot {
                    CollectionsRootView(navigationPath: $navigationPath)
                } else if !isUITestingHost && !syncService.isLocalDataLoaded
                            || (!isUITestingHost
                                && syncService.connectionState == .connecting
                                && syncService.collectionEntries.isEmpty) {
                    ProgressView(Bundle.currentLocalizedString("recipe.list.loading"))
                        .mobileTimerPanelBottomPadding()
                } else if !hasAnyRows {
                    if isSearching {
                        ContentUnavailableView {
                            AppEmptyState.label("recipe.list.search-empty.title", symbol: "magnifyingglass")
                        }
                        .font(AppTypography.body)
                        .mobileTimerPanelBottomPadding()
                    } else {
                        ContentUnavailableView {
                            AppEmptyState.label("recipe.list.empty.title", symbol: "fork.knife")
                        } description: {
                            Text("recipe.list.empty.description")
                                .appBody()
                        }
                        .font(AppTypography.body)
                        .mobileTimerPanelBottomPadding()
                    }
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
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeList)
                }
                }
            }
            .searchable(text: $searchText, prompt: Text("search.recipes"))
            .onAppear {
                searchStore.bind(syncService: syncService)
            }
            .onChange(of: searchText) { _, query in
                // Tokens computed once per change (was: 16–26× per render).
                searchTokens = RecipeSearchUtils.tokenizeQuery(query)
                let sorted = RecipeTitleEmoji.sortCollectionEntries(syncService.collectionEntries)
                searchStore.refresh(entries: sorted, query: query)
            }
            .localizedNavigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .appListBodyTypography()
            .navigationDestination(for: RecipesRoute.self) { route in
                switch route {
                case .folder(let folderId):
                    CollectionFolderView(
                        folderId: folderId,
                        navigationPath: $navigationPath
                    )
                case .recipe(let recipeId, _, let openInEditMode):
                    YDocRecipeDetailView(
                        recipeId: recipeId,
                        startInEditMode: openInEditMode
                    )
                    .recipeZoomTransitionDestination(recipeId: recipeId, in: recipeZoomNamespace)
                }
            }
            #if DEBUG
            .onChange(of: syncService.collectionEntries.count) { _, _ in
                openDebugRecipeIfNeeded()
            }
            .task {
                openDebugRecipeIfNeeded()
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    viewModeMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { @MainActor in
                            await handleCreateRecipe(folderId: nil)
                        }
                    } label: {
                        AppToolbarStyle.iconOnly(systemName: "plus")
                    }
                    .appToolbarIconButton()
                    .disabled(isCreatingRecipe)
                    .accessibilityLabel("recipes.add-button")
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeListAdd)
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .assign(let recipeId, let recipeName):
                    CollectionAssignSheet(recipeId: recipeId, recipeName: recipeName)
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
                }
            }

        }
    }

    // MARK: - View mode menu (Files-style principal dropdown)

    private var viewModeSelection: Binding<RecipeFolderRoutes.ViewMode> {
        Binding(
            get: { viewMode },
            set: { viewModeRaw = $0.rawValue }
        )
    }

    private var viewModeMenuTitleKey: LocalizedStringKey {
        viewMode == .flat ? "collections.view-flat" : "collections.view-collections"
    }

    @ViewBuilder
    private var viewModeMenu: some View {
        Menu {
            Picker("collections.title", selection: viewModeSelection) {
                Label {
                    Text("collections.view-flat")
                } icon: {
                    AppSymbol.image("list.bullet")
                }
                .tag(RecipeFolderRoutes.ViewMode.flat)

                Label {
                    Text("collections.view-collections")
                } icon: {
                    AppSymbol.image("folder")
                }
                .tag(RecipeFolderRoutes.ViewMode.collections)
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModeMenuTitleKey)
                    .font(AppTypography.body)
                    .foregroundStyle(Color.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
        }
        .accessibilityLabel(Text("collections.title"))
    }

    // MARK: - Collection actions

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
            if !navigationPath.isEmpty {
                navigationPath = NavigationPath()
            }
        } catch {
            presentedAlert = .error(UserFacingAPIError.message(for: error))
        }
    }

    private func handleCreateRecipe(folderId: String?) async {
        guard !isCreatingRecipe else { return }
        isCreatingRecipe = true
        defer { isCreatingRecipe = false }

        do {
            let recipeId = try await syncService.createRecipe()

            let shouldAssignFolder: Bool = folderId.map { id in
                !CollectionVirtualFolders.isKnownVirtualFolderId(id)
            } ?? false
            if shouldAssignFolder, let folderId {
                do {
                    try await syncService.setRecipeFolders(recipeId: recipeId, folderIds: [folderId])
                } catch {
                    presentedAlert = .error(UserFacingAPIError.message(for: error))
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

    @ViewBuilder
    private func recipeRows(_ items: [RecipeRowData]) -> some View {
        ForEach(items) { item in
            ZStack(alignment: .leading) {
                EquatableView(
                    content: RecipeRowEquatable(
                        data: item,
                        highlight: isSearching ? searchStore.highlights[item.id] : nil,
                        allowsNetworkRefresh: allowsImageNetworkRefresh,
                        zoomNamespace: recipeZoomNamespace
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                NavigationLink(value: RecipesRoute.recipe(recipeId: item.id, folderContext: nil)) {
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
                    presentedSheet = .assign(recipeId: item.id, recipeName: item.displayName)
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
                    presentedAlert = .deleteRecipe(item)
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

    #if DEBUG
    private func openDebugRecipeIfNeeded() {
        guard !didOpenDebugRecipe,
              let recipeId = DebugLaunchOptions.openRecipeId,
              syncService.collectionEntries.contains(where: { $0.id == recipeId && !$0.deleted }) else {
            return
        }
        didOpenDebugRecipe = true
        navigationPath.append(RecipesRoute.recipe(recipeId: recipeId, folderContext: nil))
    }
    #endif
}

// MARK: - Modal presentation state

private enum RecipeListSheet: Identifiable {
    case assign(recipeId: String, recipeName: String)

    var id: String {
        switch self {
        case .assign(let recipeId, _):
            "assign-\(recipeId)"
        }
    }
}

private enum RecipeListAlert: Identifiable {
    case deleteRecipe(RecipeRowData)
    case error(String)

    var id: String {
        switch self {
        case .deleteRecipe(let row):
            "delete-\(row.id)"
        case .error(let message):
            "error-\(message.hashValue)"
        }
    }
}

private enum RecipeListMetrics {
    static let colorDotSide: CGFloat = 12
    static let emojiFontSize: CGFloat = 18
    static let thumbnailSide: CGFloat = RecipeRowLayoutMetrics.recipeListThumbnailSide
}

// MARK: - Section chrome (internal — shared with CollectionFolderView)

struct RecipeListSectionHeader: View {
    let isPinnedSection: Bool

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            if isPinnedSection {
                AppSymbol.image("pin")
                    .font(AppTypography.iconSize(AppTypography.footnoteSize))
                    .frame(
                        width: RecipeRowLayoutMetrics.markerSlotWidth,
                        height: RecipeRowLayoutMetrics.footnoteLineHeight,
                        alignment: .center
                    )
            }

            Text(
                isPinnedSection
                    ? "recipe.list.section.pinned"
                    : "recipe.list.section.unpinned"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(AppTypography.footnote)
        .foregroundStyle(.secondary)
        .tracking(AppSectionHeader.usesUpperCase ? AppSectionHeader.letterSpacing : 0)
        .textCase(AppSectionHeader.usesUpperCase ? .uppercase : nil)
    }
}

extension View {
    func recipeListSectionHeaderRow() -> some View {
        self
            .padding(.top, 14)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: RecipeRowLayoutMetrics.listHorizontalInset,
                    bottom: 0,
                    trailing: RecipeRowLayoutMetrics.listHorizontalInset
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Row marker slot (emoji or color dot in one frame)

private struct RecipeRowMarkerSlot: View {
    let emoji: String?
    let color: String?

    var body: some View {
        ZStack {
            if let emoji {
                Text(emoji)
                    .font(.system(size: RecipeListMetrics.emojiFontSize))
                    .fixedSize()
            } else {
                Circle()
                    .fill(RecipeAccentColor.color(from: color ?? "oklch(0.65 0.25 270)"))
                    .frame(
                        width: RecipeListMetrics.colorDotSide,
                        height: RecipeListMetrics.colorDotSide
                    )
            }
        }
        .frame(
            width: RecipeRowLayoutMetrics.markerSlotWidth,
            height: RecipeRowLayoutMetrics.titleLineHeight,
            alignment: .center
        )
    }
}

// MARK: - Database init warning

private struct DatabaseInitFailedBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppSymbol.image("exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("database.error.in-memory-fallback.title")
                    .appHeadline()
                Text("database.error.in-memory-fallback.description")
                    .appFootnote()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Recipe Row

private struct RecipeRowEquatable: View, Equatable {
    let data: RecipeRowData
    let highlight: RecipeRowHighlight?
    let allowsNetworkRefresh: Bool
    let zoomNamespace: Namespace.ID?

    var body: some View {
        RecipeRow(
            data: data,
            highlight: highlight,
            allowsNetworkRefresh: allowsNetworkRefresh,
            zoomNamespace: zoomNamespace
        )
    }
}

struct RecipeRow: View {
    let data: RecipeRowData
    /// Pre-built highlighted title + snippet. Built once by
    /// `RecipeListSearchStore` per query, not per render. `nil` when search is
    /// inactive — the row renders a plain `Text` title.
    var highlight: RecipeRowHighlight? = nil
    var allowsNetworkRefresh: Bool = true
    /// Optional namespace for the iOS 26+ zoom-morph transition into recipe
    /// detail. `nil` disables the transition anchor (e.g. outside the main list).
    var zoomNamespace: Namespace.ID? = nil

    private var hasThumbnail: Bool { data.hasThumbnail }

    private var titleText: String {
        let trimmed = data.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "recipe.list.no-title")
        }
        return trimmed
    }

    /// Zero spacing when there is no snippet, so the row matches the old
    /// title-only layout when search is inactive.
    private var snippetSpacing: CGFloat {
        guard highlight?.snippet != nil else { return 0 }
        return RecipeRowLayoutMetrics.searchSnippetSpacing
    }

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            RecipeRowMarkerSlot(
                emoji: data.leadingEmoji,
                color: data.color
            )

            VStack(alignment: .leading, spacing: snippetSpacing) {
                titleLabel
                if let snippet = highlight?.snippet {
                    Text(snippet)
                        .lineSpacing(AppTypography.footnoteLineSpacing)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ingredientListRowChrome()
        .padding(.trailing, hasThumbnail ? RecipeListMetrics.thumbnailSide + 12 : 0)
        .overlay(alignment: .trailing) {
            if hasThumbnail {
                recipeThumbnail
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var titleLabel: some View {
        if let titleAttr = highlight?.title {
            Text(titleAttr)
                .lineSpacing(AppTypography.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        } else {
            Text(titleText)
                .appBody()
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }

    private var recipeThumbnail: some View {
        RecipeCachedImageView(
            recipeId: data.id,
            imageUrl: data.imageUrl,
            variant: .preview,
            allowsNetworkRefresh: allowsNetworkRefresh
        )
        .frame(width: RecipeListMetrics.thumbnailSide, height: RecipeListMetrics.thumbnailSide)
        .clipped()
        .modifier(RecipeRowZoomSourceModifier(
            recipeId: data.id,
            namespace: zoomNamespace
        ))
    }
}

// MARK: - Value Type

struct RecipeRowData: Identifiable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let leadingEmoji: String?
    let color: String?
    let imageUrl: String?
    let isPinned: Bool

    var hasThumbnail: Bool {
        guard let imageUrl, !imageUrl.isEmpty else { return false }
        return true
    }

    init(entry: CollectionEntry) {
        id = entry.id
        name = entry.name
        leadingEmoji = RecipeTitleEmoji.leadingEmoji(in: entry.name)
        displayName = RecipeTitleEmoji.displayName(for: entry.name)
        color = entry.color
        imageUrl = entry.imageUrl
        isPinned = entry.isPinned
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    RecipeListView()
        .environment({
            let database = try! YrsDatabase()
            let store = YDocStore(dbQueue: database.dbQueue)
            return YjsSyncService(store: store)
        }())
}
