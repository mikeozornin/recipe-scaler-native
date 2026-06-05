import SwiftUI
import UIKit

struct RecipeListView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @Binding var navigationPath: NavigationPath
    @State private var searchText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSyncStatus = false
    @State private var recipePendingDelete: RecipeRowData?
    @State private var isCreatingRecipe = false
    @State private var recipeIdToOpenInEditMode: String?


    init(navigationPath: Binding<NavigationPath> = .constant(NavigationPath())) {
        _navigationPath = navigationPath
    }
    #if DEBUG
    @State private var didOpenDebugRecipe = false
    #endif

    private var filteredEntries: [CollectionEntry] {
        let sorted = RecipeTitleEmoji.sortCollectionEntries(syncService.collectionEntries)
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return sorted
        }

        let tokens = tokenizeQuery(trimmed)
        return sorted.filter { entry in
            tokens.allSatisfy { token in
                normalizeForSearch(entry.name).contains(token)
            }
        }
    }

    private var pinnedRowItems: [RecipeRowData] {
        filteredEntries
            .filter(\.isPinned)
            .map(RecipeRowData.init(entry:))
    }

    private var unpinnedRowItems: [RecipeRowData] {
        filteredEntries
            .filter { !$0.isPinned }
            .map(RecipeRowData.init(entry:))
    }

    private var hasAnyRows: Bool {
        !pinnedRowItems.isEmpty || !unpinnedRowItems.isEmpty
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if syncService.connectionState == .connecting && syncService.collectionEntries.isEmpty {
                    ProgressView(String(localized: "recipe.list.loading"))
                } else if !hasAnyRows {
                    ContentUnavailableView {
                        AppLabel.make(String(localized: "recipe.list.empty.title"), symbol: "fork.knife")
                    } description: {
                        Text(String(localized: "Your recipes will appear here"))
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
                    }
                    .listStyle(.plain)
                    .listSectionSpacing(0)
                    .padding(.top, -10)
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeList)
                    .searchable(text: $searchText, prompt: "Search recipes")
                }
            }
            .navigationTitle("Recipes")
            .appListBodyTypography()
            .navigationDestination(for: String.self) { recipeId in
                YDocRecipeDetailView(
                    recipeId: recipeId,
                    startInEditMode: recipeIdToOpenInEditMode == recipeId
                )
                .onAppear {
                    if recipeIdToOpenInEditMode == recipeId {
                        recipeIdToOpenInEditMode = nil
                    }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await handleAddRecipe() }
                    } label: {
                        AppToolbarStyle.labeledIcon(
                            systemName: "plus",
                            title: String(localized: "recipe.list.add")
                        )
                    }
                    .appToolbarIconButton()
                    .disabled(isCreatingRecipe)
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeListAdd)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SyncStatusIndicator(
                        connectionState: syncService.connectionState,
                        imageCacheStatus: syncService.imageCacheStatus,
                        recipeDocumentCacheStatus: syncService.recipeDocumentCacheStatus
                    ) {
                        showingSyncStatus = true
                    }
                }
            }
            .sheet(isPresented: $showingSyncStatus) {
                SyncStatusSheet(
                    connectionState: syncService.connectionState,
                    connectionTransport: syncService.connectionTransport,
                    imageCacheStatus: syncService.imageCacheStatus,
                    recipeDocumentCacheStatus: syncService.recipeDocumentCacheStatus,
                    onRetryImageDownload: {
                        syncService.retryImagePrefetch()
                    },
                    onRetryRecipeDocumentsDownload: {
                        syncService.retryRecipeDocumentsBatchLoad()
                    }
                )
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

        }
    }

    // MARK: - Collection actions

    private func handleAddRecipe() async {
        guard !isCreatingRecipe else { return }
        isCreatingRecipe = true
        defer { isCreatingRecipe = false }
        do {
            let recipeId = try await syncService.createRecipe()
            recipeIdToOpenInEditMode = recipeId
            navigationPath.append(recipeId)
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

    @ViewBuilder
    private func recipeRows(_ items: [RecipeRowData]) -> some View {
        ForEach(items) { item in
            ZStack(alignment: .leading) {
                RecipeRow(
                    data: item,
                    allowsNetworkRefresh: allowsImageNetworkRefresh
                )

                NavigationLink(value: item.id) {
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
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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

    #if DEBUG
    private func openDebugRecipeIfNeeded() {
        guard !didOpenDebugRecipe,
              let recipeId = DebugLaunchOptions.openRecipeId,
              syncService.collectionEntries.contains(where: { $0.id == recipeId && !$0.deleted }) else {
            return
        }
        didOpenDebugRecipe = true
        navigationPath.append(recipeId)
    }
    #endif

    // MARK: - Search Helpers

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
                    let phrase = String(remaining)
                    tokens.append(normalizeForSearch(phrase))
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
        return value
            .trimmingCharacters(in: .whitespaces)
            .decomposedStringWithCanonicalMapping
            .components(separatedBy: CharacterSet(charactersIn: "\u{0300}"..."\u{036F}"))
            .joined()
            .lowercased()
    }
}

private enum RecipeListMetrics {
    static let colorDotSide: CGFloat = 12
    static let emojiFontSize: CGFloat = 18
    static let thumbnailSide: CGFloat = 44
}

// MARK: - Section chrome

private struct RecipeListSectionHeader: View {
    let isPinnedSection: Bool

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            if isPinnedSection {
                AppSymbol.image("pin")
                    .font(AppTypography.iconSize(AppTypography.calloutSize))
                    .frame(
                        width: RecipeRowLayoutMetrics.markerSlotWidth,
                        height: RecipeRowLayoutMetrics.titleLineHeight,
                        alignment: .center
                    )
            }

            Text(
                isPinnedSection
                    ? String(localized: "recipe.list.section.pinned")
                    : String(localized: "recipe.list.section.unpinned")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(AppTypography.compact)
        .foregroundStyle(.secondary)
    }
}

private extension View {
    /// Web: `px-4 pt-2 pb-0 text-sm` — same leading grid as recipe rows (16 + 22 pt slot).
    func recipeListSectionHeaderRow() -> some View {
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

// MARK: - Sync + image cache indicator

private struct SyncStatusIndicator: View {
    let connectionState: ConnectionState
    let imageCacheStatus: RecipeImageCacheStatus
    let recipeDocumentCacheStatus: RecipeDocumentCacheStatus
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                connectionGlyph
                    .font(AppTypography.footnote)

                if recipeDocumentCacheStatus.totalRecipes > 0 {
                    recipeDocumentBadge
                        .font(AppTypography.footnote)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                if imageCacheStatus.recipesWithImage > 0 {
                    imageCacheBadge
                        .font(AppTypography.footnote)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var connectionGlyph: some View {
        switch connectionState {
        case .connecting, .reconnecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            AppSymbol.image("checkmark.circle")
                .foregroundStyle(connectionTint)
        case .error:
            AppSymbol.image("exclamationmark.circle")
                .foregroundStyle(.red)
        case .disconnected:
            AppSymbol.image("wifi.slash")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recipeDocumentBadge: some View {
        if recipeDocumentCacheStatus.isDownloading {
            AppSymbol.image("arrow.down.doc.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .indigo)
        } else if recipeDocumentCacheStatus.isFullyCached {
            AppSymbol.image("doc.fill")
                .foregroundStyle(.green)
        } else {
            AppSymbol.image("doc.badge.exclamationmark.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .orange)
        }
    }

    @ViewBuilder
    private var imageCacheBadge: some View {
        if imageCacheStatus.isDownloading {
            AppSymbol.image("arrow.down.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .blue)
        } else if imageCacheStatus.isFullyCached {
            AppSymbol.image("photo.fill")
                .foregroundStyle(.green)
        } else {
            AppSymbol.image("photo.badge.exclamationmark.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .orange)
        }
    }

    private var connectionTint: Color {
        if recipeDocumentCacheStatus.totalRecipes > 0, !recipeDocumentCacheStatus.isFullyCached {
            return .orange
        }
        if imageCacheStatus.recipesWithImage > 0, !imageCacheStatus.isFullyCached {
            return .orange
        }
        return .green
    }

    private var accessibilityLabel: String {
        var parts = [connectionState.displayLabel]
        if recipeDocumentCacheStatus.totalRecipes > 0 {
            parts.append(
                String(
                    format: String(localized: "sync.status.a11y.recipes"),
                    locale: .current,
                    recipeDocumentCacheStatus.cachedRecipes,
                    recipeDocumentCacheStatus.totalRecipes
                )
            )
        }
        if imageCacheStatus.recipesWithImage > 0 {
            parts.append(
                String(
                    format: String(localized: "sync.status.a11y.images"),
                    locale: .current,
                    imageCacheStatus.fullCached,
                    imageCacheStatus.recipesWithImage
                )
            )
        }
        return parts.joined(separator: ", ")
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

// MARK: - Recipe Row

struct RecipeRow: View {
    let data: RecipeRowData
    var allowsNetworkRefresh: Bool = true

    private var hasThumbnail: Bool { data.hasThumbnail }

    private var titleText: String {
        let trimmed = data.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "recipe.list.no-title")
        }
        return trimmed
    }

    var body: some View {
        titleRow
            .padding(.trailing, hasThumbnail ? RecipeListMetrics.thumbnailSide + 12 : 0)
            .overlay(alignment: .trailing) {
                if hasThumbnail {
                    recipeThumbnail
                }
            }
            .contentShape(Rectangle())
    }

    /// Height comes from title + marker only; thumbnail is overlaid (web: `self-center`, no stretch).
    private var titleRow: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            RecipeRowMarkerSlot(
                emoji: data.leadingEmoji,
                color: data.color
            )

            Text(titleText)
                .font(AppTypography.body)
                .foregroundColor(.primary)
                .lineSpacing(RecipeRowLayoutMetrics.wrappedLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ingredientListRowChrome()
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

// MARK: - Value Type

struct RecipeRowData: Identifiable {
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
        .environmentObject({
            let database = try! YrsDatabase()
            let store = YDocStore(dbQueue: database.dbQueue)
            return YjsSyncService(store: store)
        }())
}