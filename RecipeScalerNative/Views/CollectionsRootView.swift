import SwiftUI

/// Root view for the "By collection" mode.
///
/// Shows virtual folders (All recipes, Uncategorized), user folders
/// with recipe counts, and an inline "New collection" create row.
struct CollectionsRootView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @Binding var navigationPath: NavigationPath

    @State private var isCreatingNew = false
    @State private var newFolderName = ""
    @State private var isSavingFolder = false
    @FocusState private var isNewFieldFocused: Bool

    var body: some View {
        List {
            // Virtual: All recipes
            collectionRow(
                folderId: CollectionVirtualFolders.allRecipesFolderId,
                title: String(localized: "collections.all-recipes"),
                icon: "list.bullet",
                count: syncService.collectionIndex.live.count
            )

            // User folders
            let sortedFolders = RecipeFolder.sortedActive(syncService.folders)
            ForEach(sortedFolders, id: \.id) { folder in
                collectionRow(
                    folderId: folder.id,
                    title: FolderDisplayName.displayName(forStoredName: folder.name),
                    icon: "folder",
                    count: syncService.collectionIndex.countByFolder[folder.id] ?? 0
                )
            }

            // Virtual: Uncategorized
            collectionRow(
                folderId: CollectionVirtualFolders.uncategorizedFolderId,
                title: String(localized: "collections.uncategorized"),
                icon: "folder",
                count: syncService.collectionIndex.uncategorized.count
            )

            // Inline create
            newCollectionRow

            MobileTimerPanelListSpacerRow()
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 1)
    }

    // MARK: - Collection row

    @ViewBuilder
    private func collectionRow(
        folderId: String,
        title: String,
        icon: String,
        count: Int
    ) -> some View {
        Button {
            navigationPath.append(RecipesRoute.folder(folderId))
        } label: {
            HStack(spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
                AppSymbol.image(icon)
                    .font(.system(size: RecipeRowLayoutMetrics.titleFontSize))
                    .frame(
                        width: RecipeRowLayoutMetrics.markerSlotWidth,
                        height: RecipeRowLayoutMetrics.titleLineHeight,
                        alignment: .center
                    )

                Text(title)
                    .appBody()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(count)")
                    .appFootnote()
                    .foregroundStyle(.secondary)

                AppSymbol.image("chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .ingredientListRowChrome()
        }
        .buttonStyle(.plain)
        .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("collection_row_\(folderId)")
    }

    // MARK: - New collection row

    @ViewBuilder
    private var newCollectionRow: some View {
        if isCreatingNew {
            HStack(spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
                AppSymbol.image("folder.badge.plus")
                    .font(.system(size: RecipeRowLayoutMetrics.titleFontSize))
                    .frame(
                        width: RecipeRowLayoutMetrics.markerSlotWidth,
                        height: RecipeRowLayoutMetrics.titleLineHeight,
                        alignment: .center
                    )

                TextField(
                    String(localized: "collections.new-placeholder"),
                    text: $newFolderName
                )
                .appBody()
                .focused($isNewFieldFocused)
                .onSubmit {
                    commitNewFolder()
                }
            }
            .ingredientListRowChrome()
            .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
            .listRowSeparator(.hidden)
            .onAppear {
                isNewFieldFocused = true
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCreatingNew = true
                    newFolderName = ""
                }
            } label: {
                HStack(spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
                    AppSymbol.image("plus.circle")
                        .font(.system(size: RecipeRowLayoutMetrics.titleFontSize))
                        .frame(
                            width: RecipeRowLayoutMetrics.markerSlotWidth,
                            height: RecipeRowLayoutMetrics.titleLineHeight,
                            alignment: .center
                        )

                    Text("collections.new")
                        .appBody()
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .ingredientListRowChrome()
            }
            .buttonStyle(.plain)
            .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("collection_new_row")
        }
    }

    // MARK: - Actions

    private func commitNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        isNewFieldFocused = false

        guard !trimmed.isEmpty else {
            withAnimation(.easeInOut(duration: 0.15)) {
                isCreatingNew = false
                newFolderName = ""
            }
            return
        }

        guard !isSavingFolder else { return }
        isSavingFolder = true

        Task {
            do {
                _ = try await syncService.createFolder(name: trimmed)
            } catch {
                // Silently fail — user can retry.
            }
            isSavingFolder = false
            withAnimation(.easeInOut(duration: 0.15)) {
                isCreatingNew = false
                newFolderName = ""
            }
        }
    }
}
