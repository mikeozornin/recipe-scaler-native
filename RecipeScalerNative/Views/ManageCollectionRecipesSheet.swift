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

    /// Recipes in this folder (for quick lookup).
    private var memberIds: Set<String> {
        Set(
            syncService.collectionEntries
                .filter { !$0.deleted && $0.folderIds.contains(folderId) }
                .map(\.id)
        )
    }

    private var filteredRecipes: [CollectionEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allRecipes }

        let tokens = tokenizeQuery(trimmed)
        return allRecipes.filter { entry in
            tokens.allSatisfy { token in
                normalizeForSearch(entry.name).contains(token)
            }
        }
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
        RecipeSearchUtils.normalizeForSearch(value)
    }
}
