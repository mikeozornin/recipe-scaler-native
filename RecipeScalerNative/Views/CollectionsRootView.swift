import SwiftUI

/// Root view for the "By collection" mode.
///
/// Shows virtual folders (All recipes, Uncategorized), user folders
/// with recipe counts, and an inline "New collection" create row.
/// Supports two layouts: plain list and folder grid (configurable in Profile).
struct CollectionsRootView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @Binding var navigationPath: NavigationPath

    @AppStorage(RecipeFolderRoutes.collectionsRootLayoutStorageKey)
    private var layoutRaw: String = RecipeFolderRoutes.CollectionsRootLayout.list.rawValue

    @State private var isCreatingNew = false
    @State private var newFolderName = ""
    @State private var isSavingFolder = false
    @FocusState private var isNewFieldFocused: Bool

    private var layout: RecipeFolderRoutes.CollectionsRootLayout {
        RecipeFolderRoutes.CollectionsRootLayout(rawValue: layoutRaw) ?? .list
    }

    private var sortedFolders: [RecipeFolder] {
        RecipeFolder.sortedActive(syncService.folders)
    }

    private var uncategorizedCount: Int {
        syncService.collectionIndex.uncategorized.count
    }

    var body: some View {
        if !syncService.isLocalDataLoaded {
            ProgressView(Bundle.currentLocalizedString("recipe.list.loading"))
                .mobileTimerPanelBottomPadding()
        } else {
            switch layout {
            case .list:
                listContent
            case .folders:
                gridContent
            }
        }
    }

    // MARK: - List layout

    @ViewBuilder
    private var listContent: some View {
        List {
            collectionRow(
                folderId: CollectionVirtualFolders.allRecipesFolderId,
                title: Bundle.currentLocalizedString("collections.all-recipes"),
                icon: "list.bullet",
                count: syncService.collectionIndex.live.count
            )

            ForEach(sortedFolders, id: \.id) { folder in
                let count = syncService.collectionIndex.countByFolder[folder.id] ?? 0
                collectionRow(
                    folderId: folder.id,
                    title: FolderDisplayName.displayName(forStoredName: folder.name),
                    icon: RecipeFolderConstants.folderIconName(recipeCount: count),
                    count: count
                )
            }

            if uncategorizedCount > 0 {
                collectionRow(
                    folderId: CollectionVirtualFolders.uncategorizedFolderId,
                    title: Bundle.currentLocalizedString("collections.uncategorized"),
                    icon: RecipeFolderConstants.folderIconName(recipeCount: uncategorizedCount),
                    count: uncategorizedCount
                )
            }

            newCollectionRow

            MobileTimerPanelListSpacerRow()
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 1)
        .toolbar {
            if isCreatingNew && isNewFieldFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "collections.create")) {
                        commitNewFolder()
                    }
                    .appToolbarTextButton()
                    .disabled(
                        newFolderName.trimmingCharacters(in: .whitespaces).isEmpty || isSavingFolder
                    )
                }
            }
        }
    }

    // MARK: - Grid (folders) layout

    @ViewBuilder
    private var gridContent: some View {
        ScrollView {
            let columns = [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ]

            LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                // Virtual "All recipes" — first tile
                folderGridTile(
                    folderId: CollectionVirtualFolders.allRecipesFolderId,
                    title: Bundle.currentLocalizedString("collections.all-recipes"),
                    count: syncService.collectionIndex.live.count
                )

                // User folders
                ForEach(sortedFolders, id: \.id) { folder in
                    folderGridTile(
                        folderId: folder.id,
                        title: FolderDisplayName.displayName(forStoredName: folder.name),
                        count: syncService.collectionIndex.countByFolder[folder.id] ?? 0,
                        folder: folder
                    )
                }

                // Virtual "Without collection" — gray when present
                if uncategorizedCount > 0 {
                    folderGridTile(
                        folderId: CollectionVirtualFolders.uncategorizedFolderId,
                        title: Bundle.currentLocalizedString("collections.uncategorized"),
                        count: uncategorizedCount
                    )
                }

                // New collection tile
                newCollectionGridTile
            }
            .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
            .padding(.top, 16)

            MobileTimerPanelListSpacerRow()
        }
        .toolbar {
            if isCreatingNew && isNewFieldFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "collections.create")) {
                        commitNewFolder()
                    }
                    .appToolbarTextButton()
                    .disabled(
                        newFolderName.trimmingCharacters(in: .whitespaces).isEmpty || isSavingFolder
                    )
                }
            }
        }
    }

    // MARK: - Folder grid tile

    @ViewBuilder
    private func folderGridTile(
        folderId: String,
        title: String,
        count: Int = 0,
        folder: RecipeFolder? = nil
    ) -> some View {
        Button {
            navigationPath.append(RecipesRoute.folder(folderId))
        } label: {
            folderGridTileContent(
                icon: RecipeFolderConstants.folderIconName(recipeCount: count),
                iconColor: RecipeAccentColor.folderIconColor(folderId: folderId, folder: folder),
                title: title,
                count: count
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(title), \(count)"))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityIdentifiers.collectionsRootGridTile(folderId: folderId))
    }

    @ViewBuilder
    private func folderGridTileContent(
        icon: String,
        iconColor: Color,
        title: String,
        count: Int
    ) -> some View {
        VStack(spacing: CollectionGridTileMetrics.iconToTextSpacing) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(iconColor)
                .frame(height: CollectionGridTileMetrics.iconHeight)

            VStack(spacing: CollectionGridTileMetrics.labelSpacing) {
                Text(title)
                    .appFootnote()
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(count)")
                    .font(AppTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(
                minHeight: CollectionGridTileMetrics.textBlockMinHeight,
                alignment: .top
            )
        }
    }

    // MARK: - New collection grid tile

    @ViewBuilder
    private var newCollectionGridTile: some View {
        if isCreatingNew {
            VStack(spacing: CollectionGridTileMetrics.iconToTextSpacing) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .frame(height: CollectionGridTileMetrics.iconHeight)

                TextField(
                    String(localized: "collections.new-placeholder"),
                    text: $newFolderName
                )
                .font(AppTypography.footnote)
                .focused($isNewFieldFocused)
                .submitLabel(.done)
                .multilineTextAlignment(.center)
                .onSubmit {
                    commitNewFolder()
                }
                .frame(
                    minHeight: CollectionGridTileMetrics.textBlockMinHeight,
                    alignment: .top
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                VStack(spacing: CollectionGridTileMetrics.iconToTextSpacing) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                        .frame(height: CollectionGridTileMetrics.iconHeight)

                    Text("collections.new")
                        .appFootnote()
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(
                            minHeight: CollectionGridTileMetrics.textBlockMinHeight,
                            alignment: .top
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("collections.new"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityIdentifiers.collectionsNewRow)
        }
    }

    // MARK: - Collection row

    @ViewBuilder
    private func collectionRow(
        folderId: String,
        title: String,
        icon: String,
        count: Int
    ) -> some View {
        let folder = syncService.folders.first { $0.id == folderId }

        Button {
            navigationPath.append(RecipesRoute.folder(folderId))
        } label: {
            HStack(spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
                AppSymbol.image(icon)
                    .font(.system(size: RecipeRowLayoutMetrics.titleFontSize))
                    .foregroundStyle(RecipeAccentColor.folderIconColor(folderId: folderId, folder: folder))
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
        .accessibilityIdentifier(AccessibilityIdentifiers.collectionsRootRow(folderId: folderId))
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
                .font(AppTypography.body)
                .focused($isNewFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    commitNewFolder()
                }
            }
            .ingredientListRowChrome()
            .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
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
                    AppSymbol.image("plus")
                        .font(.system(size: RecipeRowLayoutMetrics.titleFontSize))
                        .frame(
                            width: RecipeRowLayoutMetrics.markerSlotWidth,
                            height: RecipeRowLayoutMetrics.titleLineHeight,
                            alignment: .center
                        )

                    Text("collections.new")
                        .appBody()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.primary)
                .ingredientListRowChrome()
            }
            .buttonStyle(.plain)
            .tint(.primary)
            .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
            .accessibilityIdentifier(AccessibilityIdentifiers.collectionsNewRow)
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

/// Fixed slot heights so folder icons top-align across a grid row.
private enum CollectionGridTileMetrics {
    static let iconHeight: CGFloat = 48
    static let iconToTextSpacing: CGFloat = 4
    /// Gap between title and recipe count.
    static let labelSpacing: CGFloat = 4
    /// Two-line title + 4pt gap + count; minHeight keeps row tops aligned, content hugs top.
    static let textBlockMinHeight: CGFloat = 56
}
