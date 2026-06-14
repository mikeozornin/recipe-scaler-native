import SwiftUI

/// Sheet for assigning a recipe to one or more collections.
///
/// Presented from swipe actions (collections) or the recipe detail menu.
/// Shows all active collections with checkmarks for current membership;
/// "Done" writes the full `folderIds` set in one transaction.
struct CollectionAssignSheet: View {
    let recipeId: String
    let recipeName: String

    @EnvironmentObject private var syncService: YjsSyncService
    @Environment(\.dismiss) private var dismiss

    /// Local working copy of selected folder ids (committed on Done).
    @State private var selectedFolderIds: Set<String> = []
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""

    @State private var isCreatingNew = false
    @State private var newFolderName = ""
    @State private var isSavingFolder = false
    @FocusState private var isNewFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                let sortedFolders = RecipeFolder.sortedActive(syncService.folders)
                if sortedFolders.isEmpty && !isCreatingNew {
                    ContentUnavailableView {
                        AppLabel.make(String(localized: "collections.assign-empty"), symbol: "folder.badge.plus")
                    }
                } else {
                    List {
                        ForEach(sortedFolders, id: \.id) { folder in
                            Button {
                                toggleFolder(folder.id)
                            } label: {
                                HStack {
                                    Text(FolderDisplayName.displayName(forStoredName: folder.name))
                                        .appBody()
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Spacer()

                                    if selectedFolderIds.contains(folder.id) {
                                        AppSymbol.image("checkmark")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        newCollectionRow
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(Text(verbatim: Bundle.currentLocalizedString("collections.assign-title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "collections.done")) {
                        Task { await saveAndDismiss() }
                    }
                    .disabled(isSaving)
                }
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
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadCurrentMembership()
            }
        }
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
                    AppSymbol.image("plus.circle")
                        .font(.system(size: RecipeRowLayoutMetrics.titleFontSize))
                        .frame(
                            width: RecipeRowLayoutMetrics.markerSlotWidth,
                            height: RecipeRowLayoutMetrics.titleLineHeight,
                            alignment: .center
                        )

                    Text("collections.new")
                        .appBody()
                }
                .foregroundStyle(.primary)
                .ingredientListRowChrome()
            }
            .buttonStyle(.plain)
            .tint(.primary)
            .listRowInsets(RecipeRowLayoutMetrics.newCollectionRowInsets)
        }
    }

    // MARK: - Actions

    private func loadCurrentMembership() {
        if let entry = syncService.collectionEntries.first(where: { $0.id == recipeId }) {
            selectedFolderIds = Set(entry.folderIds)
        }
    }

    private func toggleFolder(_ folderId: String) {
        if selectedFolderIds.contains(folderId) {
            selectedFolderIds.remove(folderId)
        } else {
            selectedFolderIds.insert(folderId)
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func saveAndDismiss() async {
        guard !isSaving else { return }
        isSaving = true

        do {
            try await syncService.setRecipeFolders(
                recipeId: recipeId,
                folderIds: Array(selectedFolderIds)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            isSaving = false
        }
    }

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
                let newId = try await syncService.createFolder(name: trimmed)
                selectedFolderIds.insert(newId)
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isSavingFolder = false
            withAnimation(.easeInOut(duration: 0.15)) {
                isCreatingNew = false
                newFolderName = ""
            }
        }
    }
}
