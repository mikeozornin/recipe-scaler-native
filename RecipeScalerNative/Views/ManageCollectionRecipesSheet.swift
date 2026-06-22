import SwiftUI

/// Sheet for managing recipe membership in a user collection folder.
///
/// Shows all live recipes with checkboxes; checked = recipe is in this folder.
/// Toggle updates `folderIds` for that recipe immediately.
struct ManageCollectionRecipesSheet: View {
    let folderId: String

    @Environment(YjsSyncService.self) private var syncService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var memberIds: Set<String> = []
    /// Lazy recipe loader + highlight cache scoped to this sheet.
    @State private var searchStore = RecipeListSearchStore()
    /// Tokens derived from `searchText` once per change.
    @State private var searchTokens: [String] = []

    private var folder: RecipeFolder? {
        syncService.folders.first { $0.id == folderId }
    }

    private var folderDisplayName: String {
        guard let folder else { return "" }
        return FolderDisplayName.displayName(forStoredName: folder.name)
    }

    /// All live recipes sorted for display.
    private var allRecipes: [CollectionEntry] {
        RecipeTitleEmoji.sortCollectionEntries(
            syncService.collectionEntries.filter { !$0.deleted }
        )
    }

    private var isSearching: Bool {
        !searchTokens.isEmpty
    }

    /// Entries to render: precomputed filtered snapshot when searching, full
    /// list otherwise.
    private var filteredRecipes: [CollectionEntry] {
        if isSearching {
            return searchStore.filteredSnapshot
        }
        return allRecipes
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredRecipes) { recipe in
                    let isMember = memberIds.contains(recipe.id)
                    Button {
                        Task { await toggleMembership(recipeId: recipe.id, isMember: isMember) }
                    } label: {
                        let hasThumbnail = recipe.imageUrl.map { !$0.isEmpty } ?? false
                        HStack(alignment: .center, spacing: 12) {
                            AppSymbol.image(isMember ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isMember ? .accentColor : .secondary)
                                .font(.system(size: 20))

                            Text(RecipeTitleEmoji.displayName(for: recipe.name))
                                .appBody()
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .ingredientListRowChrome()
                        }
                        .padding(.trailing, hasThumbnail ? RecipeRowLayoutMetrics.recipeListThumbnailSide + 12 : 0)
                        .overlay(alignment: .trailing) {
                            if hasThumbnail, let imageUrl = recipe.imageUrl {
                                RecipeCachedImageView(
                                    recipeId: recipe.id,
                                    imageUrl: imageUrl,
                                    variant: .preview,
                                    allowsNetworkRefresh: false
                                )
                                .frame(
                                    width: RecipeRowLayoutMetrics.recipeListThumbnailSide,
                                    height: RecipeRowLayoutMetrics.recipeListThumbnailSide
                                )
                                .clipped()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .searchable(text: $searchText, prompt: Text("search.recipes"))
            .navigationTitle(Text(verbatim: folderDisplayName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "collections.done")) {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                searchStore.bind(syncService: syncService)
                refreshMemberIds()
            }
            .onChange(of: searchText) { _, query in
                searchTokens = RecipeSearchUtils.tokenizeQuery(query)
                searchStore.refresh(entries: allRecipes, query: query)
            }
            .onChange(of: syncService.collectionEntries.map(\.id)) { _, _ in
                refreshMemberIds()
                if isSearching {
                    searchStore.refresh(entries: allRecipes, query: searchText)
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleMembership(recipeId: String, isMember: Bool) async {
        var currentFolderIds: [String] = []
        if let entry = syncService.collectionEntries.first(where: { $0.id == recipeId }) {
            currentFolderIds = entry.folderIds
        }

        if isMember {
            currentFolderIds.removeAll { $0 == folderId }
        } else {
            if !currentFolderIds.contains(folderId) {
                currentFolderIds.append(folderId)
            }
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        do {
            try await syncService.setRecipeFolders(recipeId: recipeId, folderIds: currentFolderIds)
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
            showingError = true
        }
    }

    // MARK: - Member-id cache

    /// Recompute `memberIds` once per structural change to `collectionEntries`,
    /// instead of on every re-render.
    private func refreshMemberIds() {
        memberIds = Set(
            syncService.collectionEntries
                .filter { !$0.deleted && $0.folderIds.contains(folderId) }
                .map(\.id)
        )
    }
}
