import SwiftUI
import AppKit
import RecipeScalerCore

// MARK: - Discover

/// macOS Discover surface. The data and routes are shared with iOS, while the
/// presentation uses a table/list rather than the compact card stack.
struct MacDiscoverView: View {
    @Binding var path: NavigationPath
    @Environment(\.apiClient) private var apiClient
    @State private var model: DiscoverRootModel?
    @State private var searchText = ""

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .navigationTitle(Text("discover.title"))
                .searchable(text: $searchText, prompt: Text("search.recipes"))
                .navigationDestination(for: DiscoverRoute.self) { route in
                    switch route {
                    case .collection(let slug):
                        MacDiscoverCollectionView(slug: slug, path: $path)
                    case .profile(let username):
                        MacDiscoverProfileView(username: username, path: $path)
                    case .recipe(let id, let allowDownloads, let imageSource, _):
                        MacDiscoverRecipeView(
                            recipeId: id,
                            allowRecipeDownloads: allowDownloads,
                            imageSource: imageSource
                        )
                    }
                }
                .task {
                    if model == nil {
                        model = DiscoverRootModel(api: apiClient)
                    }
                    await model?.load()
                }
                .refreshable {
                    await model?.load()
                }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverRoot)
    }

    @ViewBuilder
    private var rootContent: some View {
        switch model?.state {
        case .idle, .loading, .none:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                AppEmptyState.label("discover.error", symbol: "wifi.exclamationmark")
            } description: {
                Text(message).appBody()
            }
        case .loaded(let data):
            let collections = data.collections.filter { matchesSearch($0.title, $0.description) }
            let profiles = data.profiles.filter {
                matchesSearch($0.name ?? $0.username, $0.description)
            }
            if collections.isEmpty && profiles.isEmpty {
                ContentUnavailableView {
                    AppEmptyState.label("discover.empty", symbol: "sparkles")
                } description: {
                    Text("discover.empty-description").appBody()
                }
            } else {
                List {
                    if !collections.isEmpty {
                        Section("discover.curated-collections") {
                            ForEach(collections) { collection in
                                NavigationLink(value: DiscoverRoute.collection(collection.slug)) {
                                    MacDiscoverPreviewRow(
                                        title: collection.title,
                                        subtitle: collection.description,
                                        count: collection.recipeCount,
                                        imageURL: DiscoverImageURLs.collectionCover(
                                            from: collection.coverImageURL
                                        ),
                                        fallbackSymbol: "photo"
                                    )
                                }
                                .accessibilityIdentifier(AccessibilityIdentifiers.discoverCollectionCard)
                            }
                        }
                    }

                    if !profiles.isEmpty {
                        Section("discover.featured-chefs") {
                            ForEach(profiles) { profile in
                                NavigationLink(value: DiscoverRoute.profile(profile.username)) {
                                    MacDiscoverPreviewRow(
                                        title: profile.name ?? profile.username,
                                        subtitle: profile.description,
                                        count: profile.recipeCount,
                                        imageURL: DiscoverImageURLs.avatar(username: profile.username),
                                        fallbackSymbol: "person.fill"
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func matchesSearch(_ title: String, _ subtitle: String?) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || (subtitle?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

private struct MacDiscoverPreviewRow: View {
    let title: String
    let subtitle: String?
    let count: Int?
    let imageURL: URL?
    let fallbackSymbol: String

    var body: some View {
        HStack(spacing: 14) {
            MacRemoteThumbnail(url: imageURL, fallbackSymbol: fallbackSymbol)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appHeadline()
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let count {
                    Text(Bundle.appPluralizedString(key: "discover.collection.recipe-count", count: count))
                        .appFootnote()
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }
}

private struct MacDiscoverCollectionView: View {
    let slug: String
    @Binding var path: NavigationPath
    @Environment(\.apiClient) private var apiClient
    @State private var model: DiscoverCollectionModel?
    @State private var searchText = ""

    var body: some View {
        Group {
            switch model?.state {
            case .idle, .loading, .none:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    AppEmptyState.label("discover.collection.not-found", symbol: "exclamationmark.triangle")
                } description: {
                    Text(message).appBody()
                }
            case .loaded(let collection):
                collectionContent(collection)
            }
        }
        .navigationTitle(Text("discover.collection.title"))
        .searchable(text: $searchText, prompt: Text("search.recipes"))
        .task(id: slug) {
            if model == nil {
                model = DiscoverCollectionModel(api: apiClient)
            }
            await model?.loadIfNeeded(slug: slug)
        }
        .refreshable {
            await model?.refresh(slug: slug)
        }
    }

    @ViewBuilder
    private func collectionContent(_ collection: CollectionWithRecipesDTO) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipes = collection.recipes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        if recipes.isEmpty {
            ContentUnavailableView {
                AppEmptyState.label("recipes.no-recipes", symbol: "book")
            }
        } else {
            List {
                if let description = collection.description, !description.isEmpty {
                    Text(description)
                        .appBody()
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(recipes) { recipe in
                    NavigationLink(
                        value: DiscoverRoute.recipe(
                            id: recipe.id,
                            imageSource: .curatedDiscover
                        )
                    ) {
                        MacDiscoverPreviewRow(
                            title: recipe.name,
                            subtitle: nil,
                            count: nil,
                            imageURL: DiscoverImageURLs.collectionRecipeCard(recipe: recipe),
                            fallbackSymbol: "book"
                        )
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.discoverRecipeCard(recipeID: recipe.id))
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct MacDiscoverProfileView: View {
    let username: String
    @Binding var path: NavigationPath
    @Environment(\.apiClient) private var apiClient
    @State private var model: DiscoverPublicProfileModel?
    @State private var searchText = ""

    var body: some View {
        Group {
            switch model?.state {
            case .idle, .loading, .none:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    AppEmptyState.label("discover.profile.not-found", symbol: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(message).appBody()
                }
            case .loaded(let response):
                profileContent(response)
            }
        }
        .navigationTitle(Text("discover.profile.title"))
        .searchable(text: $searchText, prompt: Text("search.recipes"))
        .task(id: username) {
            if model == nil {
                model = DiscoverPublicProfileModel(api: apiClient)
            }
            await model?.loadIfNeeded(username: username)
        }
        .refreshable {
            await model?.refresh(username: username)
        }
    }

    @ViewBuilder
    private func profileContent(_ response: PublicProfileResponseDTO) -> some View {
        let profile = response.profile
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipes = response.recipes.filter {
            query.isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }

        List {
            Section {
                HStack(spacing: 12) {
                    MacRemoteThumbnail(
                        url: DiscoverImageURLs.avatar(fromPublicProfile: profile.avatarUrl),
                        fallbackSymbol: "person.fill"
                    )
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name ?? profile.username)
                            .font(AppTypography.title2)
                        Text("@\(profile.username)")
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                }
                if let description = profile.description, !description.isEmpty {
                    Text(description).appBody().foregroundStyle(.secondary)
                }
            }

            Section("account.your-public-recipes") {
                if recipes.isEmpty {
                    Text("discover.profile.no-recipes")
                        .appBody()
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipes) { recipe in
                        NavigationLink(
                            value: DiscoverRoute.recipe(
                                id: recipe.id,
                                allowDownloads: profile.allowRecipeDownloads != false,
                                imageSource: .publicRecipe
                            )
                        ) {
                            MacDiscoverPreviewRow(
                                title: recipe.name,
                                subtitle: recipe.description,
                                count: nil,
                                imageURL: DiscoverImageURLs.publicRecipeCard(recipe: recipe),
                                fallbackSymbol: "book"
                            )
                        }
                        .accessibilityIdentifier(AccessibilityIdentifiers.discoverRecipeCard(recipeID: recipe.id))
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

private struct MacDiscoverRecipeView: View {
    enum LoadState {
        case idle
        case loading
        case curated(CuratedRecipeDTO)
        case publicState(PublicRecipeStateDTO)
        case failed(String)
    }

    let recipeId: String
    let allowRecipeDownloads: Bool
    let imageSource: DiscoverRecipeImageSource

    @Environment(YjsSyncService.self) private var syncService
    @State private var state: LoadState = .idle
    @State private var isCopying = false
    @State private var copyMessage: String?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    AppEmptyState.label("discover.recipe.failed", symbol: "exclamationmark.triangle")
                } description: {
                    Text(message).appBody()
                }
            case .curated(let recipe):
                curatedContent(recipe)
            case .publicState(let recipe):
                publicContent(recipe)
            }
        }
        .navigationTitle(Text("discover.recipe.title"))
        .toolbar {
            if allowRecipeDownloads {
                ToolbarItem {
                    Button {
                        Task { await copyRecipe() }
                    } label: {
                        if isCopying {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("discover.recipe.copy-to-me", systemImage: "arrow.down.to.line")
                        }
                    }
                    .disabled(isCopying)
                }
            }
        }
        .task(id: recipeId) {
            await load()
        }
    }

    @ViewBuilder
    private func curatedContent(_ recipe: CuratedRecipeDTO) -> some View {
        recipeContent(
            name: recipe.name,
            description: recipe.description,
            imageURL: DiscoverAPI.detailImageURL(recipeId: recipe.id, imageSource: .curatedDiscover),
            ingredients: recipe.ingredients.map { ingredient in
                let amount = ingredient.amount.map { String($0) } ?? ""
                return amount.isEmpty ? ingredient.name : "\(amount) \(ingredient.unit) — \(ingredient.name)"
            }
        )
    }

    @ViewBuilder
    private func publicContent(_ recipe: PublicRecipeStateDTO) -> some View {
        recipeContent(
            name: recipe.name ?? String(localized: "recipes.no-title"),
            description: nil,
            imageURL: DiscoverAPI.detailImageURL(recipeId: recipe.id, imageSource: imageSource),
            ingredients: []
        )
    }

    private func recipeContent(
        name: String,
        description: String?,
        imageURL: URL?,
        ingredients: [String]
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        default:
                            Color.secondary.opacity(0.12)
                                .overlay { AppSymbol.image("photo") }
                        }
                    }
                    .frame(maxWidth: 720, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text(name)
                    .font(AppTypography.display(AppTypography.recipeTitleSize))
                    .textSelection(.enabled)

                if let copyMessage {
                    Text(copyMessage)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                }

                if !ingredients.isEmpty {
                    Text("discover.recipe.ingredients").appHeadline()
                    ForEach(ingredients, id: \.self) { ingredient in
                        Text(ingredient).appBody()
                    }
                }

                if let description, !description.isEmpty {
                    Text("discover.recipe.steps").appHeadline()
                    Text(description).appBodySelectable()
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func load() async {
        state = .loading
        do {
            switch imageSource {
            case .curatedDiscover:
                state = .curated(try await DiscoverAPI.fetchRecipe(id: recipeId))
            case .publicRecipe:
                state = .publicState(try await DiscoverAPI.fetchPublicRecipeState(id: recipeId))
            }
        } catch {
            state = .failed(UserFacingAPIError.message(for: error))
        }
    }

    private func copyRecipe() async {
        guard !isCopying else { return }
        isCopying = true
        defer { isCopying = false }
        do {
            let newId: String
            switch imageSource {
            case .curatedDiscover:
                newId = try await DiscoverAPI.cloneRecipe(id: recipeId)
            case .publicRecipe:
                newId = try await DiscoverAPI.copyRecipe(id: recipeId)
            }
            await syncService.integrateCopiedRecipe(recipeId: newId, fallbackImageUrl: nil)
            copyMessage = String(localized: "discover.recipe.copied")
        } catch {
            copyMessage = UserFacingAPIError.message(for: error)
        }
    }
}

// MARK: - Shopping

struct MacShoppingListView: View {
    @Binding var path: NavigationPath
    @Environment(YjsSyncService.self) private var syncService
    @State private var draft = ""
    @State private var editingItemId: String?
    @State private var editingDraft = ""
    @State private var errorMessage: String?

    private var snapshot: ShoppingListSnapshot { syncService.shoppingSnapshot }

    private var toBuy: [ShoppingListItem] {
        sorted(snapshot.items.filter { !$0.purchased })
    }

    private var purchased: [ShoppingListItem] {
        sorted(snapshot.items.filter(\.purchased))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if toBuy.isEmpty {
                    ContentUnavailableView {
                        AppEmptyState.label("shopping.empty-to-buy", symbol: "cart")
                    } description: {
                        Text("shopping.add.placeholder").appBody()
                    }
                    .listRowSeparator(.hidden)
                } else {
                    Section("shopping.section.to-buy") {
                        ForEach(toBuy) { item in
                            MacShoppingRow(
                                item: item,
                                isEditing: editingItemId == item.id,
                                editingDraft: $editingDraft,
                                onToggle: { toggle(item) },
                                onEdit: { beginEditing(item) },
                                onCommitEdit: { commitEditing(item) },
                                onDelete: { remove(item) }
                            )
                        }
                        addRow
                    }
                }

                if !purchased.isEmpty {
                    Section {
                        ForEach(purchased) { item in
                            MacShoppingRow(
                                item: item,
                                isEditing: false,
                                editingDraft: $editingDraft,
                                onToggle: { toggle(item) },
                                onEdit: {},
                                onCommitEdit: {},
                                onDelete: { remove(item) }
                            )
                        }
                    } header: {
                        HStack {
                            Text("shopping.section.purchased")
                            Spacer()
                            Button("shopping.clear-bought") {
                                Task { await clearPurchased() }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle(Text("shopping.title"))
            .toolbar {
                ToolbarItem {
                    Picker("shopping.sort", selection: sortBinding) {
                        Text("shopping.sort.by-recipe").tag(ShoppingSortMode.recipe)
                        Text("shopping.sort.az").tag(ShoppingSortMode.alphabet)
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem {
                    ShareLink(item: shareText) {
                        AppToolbarStyle.iconOnly(systemName: "square.and.arrow.up")
                    }
                    .appToolbarIconButton()
                    .help(Text("shopping.share-button"))
                    .disabled(shareText.isEmpty)
                    .accessibilityIdentifier(AccessibilityIdentifiers.shoppingShareButton)
                }
            }
            .overlay(alignment: .top) {
                if let errorMessage {
                    Text(errorMessage)
                        .appFootnote()
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.shoppingList)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            AppSymbol.image("plus")
                .foregroundStyle(.secondary)
            TextField("shopping.add.placeholder", text: $draft)
                .appBodyFieldTypography()
                .textFieldStyle(.plain)
                .onSubmit { commitDraft() }
                .accessibilityIdentifier(AccessibilityIdentifiers.shoppingAddField)
        }
        .padding(.vertical, 5)
    }

    private var sortBinding: Binding<ShoppingSortMode> {
        Binding(
            get: { snapshot.meta.sortMode },
            set: { mode in Task { await run { try await syncService.setShoppingSortMode(mode) } } }
        )
    }

    private var shareText: String {
        ShoppingListPlainText.build(
            items: snapshot.items,
            headings: .init(
                misc: String(localized: "shopping.copy-text-misc"),
                untitledRecipe: String(localized: "shopping.copy-text-untitled-recipe")
            ),
            sortMode: snapshot.meta.sortMode
        )
    }

    private func sorted(_ items: [ShoppingListItem]) -> [ShoppingListItem] {
        switch snapshot.meta.sortMode {
        case .alphabet:
            return items.sorted {
                ShoppingListFromRecipe.sortName(for: $0.label)
                    .localizedCompare(ShoppingListFromRecipe.sortName(for: $1.label)) == .orderedAscending
            }
        case .recipe:
            return items.sorted {
                let left = $0.recipeName.isEmpty ? "~" : $0.recipeName
                let right = $1.recipeName.isEmpty ? "~" : $1.recipeName
                if left != right { return left.localizedCompare(right) == .orderedAscending }
                return $0.label.localizedCompare($1.label) == .orderedAscending
            }
        }
    }

    private func commitDraft() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !value.isEmpty else { return }
        Task { await run { try await syncService.addManualShoppingItem(label: value) } }
    }

    private func beginEditing(_ item: ShoppingListItem) {
        editingItemId = item.id
        editingDraft = item.label
    }

    private func commitEditing(_ item: ShoppingListItem) {
        guard editingItemId == item.id else { return }
        let value = editingDraft
        editingItemId = nil
        editingDraft = ""
        Task { await run { try await syncService.updateShoppingItemLabel(id: item.id, label: value) } }
    }

    private func toggle(_ item: ShoppingListItem) {
        Task { await run { try await syncService.setShoppingItemPurchased(id: item.id, purchased: !item.purchased) } }
    }

    private func remove(_ item: ShoppingListItem) {
        Task { await run { try await syncService.removeShoppingItem(id: item.id) } }
    }

    private func clearPurchased() async {
        await run { try await syncService.clearPurchasedShoppingItems() }
    }

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }
}

private struct MacShoppingRow: View {
    let item: ShoppingListItem
    let isEditing: Bool
    @Binding var editingDraft: String
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onCommitEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var showsDeleteButton: Bool {
        isHovered || isFocused
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                AppSymbol.image(item.purchased ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.purchased ? .secondary : .primary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(Text(item.purchased ? "shopping.mark-not-purchased" : "shopping.mark-purchased"))
            .accessibilityLabel(Text(item.purchased ? "shopping.mark-not-purchased" : "shopping.mark-purchased"))
            .accessibilityIdentifier(AccessibilityIdentifiers.shoppingItemToggle(id: item.id))

            if isEditing {
                TextField("shopping.add.placeholder", text: $editingDraft)
                    .appBodyFieldTypography()
                    .textFieldStyle(.plain)
                    .onSubmit(onCommitEdit)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .appBody()
                        .strikethrough(item.purchased)
                    if !item.recipeName.isEmpty {
                        Text(item.recipeName)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(item.purchased ? 0.55 : 1)
                .onTapGesture(count: 2, perform: onEdit)
            }

            Spacer(minLength: 0)
            if showsDeleteButton {
                Button(role: .destructive, action: onDelete) {
                    AppSymbol.image("trash")
                }
                .buttonStyle(.borderless)
                .help(Text("recipe.list.delete"))
                .accessibilityLabel(Text("recipe.list.delete"))
                .accessibilityIdentifier(AccessibilityIdentifiers.shoppingItemDelete(id: item.id))
                .transition(.opacity)
            }
        }
        .frame(minHeight: 44)
        .onHover { isHovered = $0 }
        .focusable()
        .focused($isFocused)
        .accessibilityIdentifier(AccessibilityIdentifiers.shoppingItem(id: item.id))
        .contextMenu {
            if !isEditing {
                Button("shopping.mark-purchased") { onToggle() }
            }
            Button("recipe.list.delete", role: .destructive, action: onDelete)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Profile

struct MacProfileView: View {
    @Environment(AuthService.self) private var authService
    @Environment(YjsSyncService.self) private var syncService
    @AppStorage(AppThemePreference.storageKey) private var themeRaw = AppThemePreference.system.rawValue
    @State private var displayName = ""
    @State private var username = ""
    @State private var seedPhrase = ""
    @State private var publicProfileEnabled = false
    @State private var shareMode: PublicShareMode = .one_by_one
    @State private var allowRecipeDownloads = true
    @State private var showNutrition = true
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var theme: AppThemePreference {
        AppThemePreference(rawValue: themeRaw) ?? .system
    }

    var body: some View {
        Form {
            Section("account.section.account") {
                TextField("account.profile.name", text: $displayName)
                    .onSubmit { saveDisplayName() }
                LabeledContent("account.username.label", value: username)
                if !seedPhrase.isEmpty {
                    DisclosureGroup("account.secret-phrase") {
                        Text(seedPhrase)
                            .appBodySelectable()
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                }
            }

            Section("account.section.public-recipes") {
                Toggle("account.public-profile.switch", isOn: $publicProfileEnabled)
                    .onChange(of: publicProfileEnabled) { _, value in
                        Task { await updateSharing(publicProfileEnabled: value) }
                    }
                if publicProfileEnabled {
                    Picker("account.share-mode.label", selection: $shareMode) {
                        Text("account.share-mode.one-by-one").tag(PublicShareMode.one_by_one)
                        Text("account.share-mode.all").tag(PublicShareMode.all)
                        Text("account.share-mode.with-images").tag(PublicShareMode.with_images_and_steps)
                    }
                    .onChange(of: shareMode) { _, value in
                        Task { await updateSharing(shareMode: value) }
                    }
                    Toggle("account.allow-downloads", isOn: $allowRecipeDownloads)
                        .onChange(of: allowRecipeDownloads) { _, value in
                            Task { await updateSharing(allowRecipeDownloads: value) }
                        }
                }
            }

            Section("account.section.preferences") {
                Picker("account.theme.label", selection: $themeRaw) {
                    Text("account.theme.system").tag(AppThemePreference.system.rawValue)
                    Text("account.theme.light").tag(AppThemePreference.light.rawValue)
                    Text("account.theme.dark").tag(AppThemePreference.dark.rawValue)
                }
                Toggle("account.nutrition.show", isOn: $showNutrition)
                    .onChange(of: showNutrition) { _, value in
                        Task { await updateNutrition(value) }
                    }
            }

            Section("account.sync.title") {
                LabeledContent("account.sync.title", value: syncService.connectionState.displayLabel)
                if let statusMessage {
                    Text(statusMessage).appFootnote().foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).appFootnote().foregroundStyle(.red)
                }
            }

            Section {
                Button("account.logout", role: .destructive) {
                    Task { await logout() }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("account.title"))
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task { await load() }
        .disabled(isSaving)
        .accessibilityIdentifier(AccessibilityIdentifiers.accountRoot)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let profile = AccountAPI.fetchProfile()
            async let sharing = AccountAPI.fetchSharingSettings()
            async let settings = AccountAPI.fetchUserSettings()
            let profileValue = try await profile
            let sharingValue = try await sharing
            let settingsValue = try await settings
            displayName = profileValue.name ?? ""
            username = profileValue.username ?? sharingValue.username ?? ""
            publicProfileEnabled = sharingValue.publicProfileEnabled == true
            shareMode = PublicShareMode(apiValue: sharingValue.shareMode) ?? .one_by_one
            allowRecipeDownloads = sharingValue.allowRecipeDownloads != false
            showNutrition = settingsValue.nutritionEnabled ?? true
            seedPhrase = (try? authService.getSeedPhrase()) ?? ""
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func saveDisplayName() {
        let value = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await AccountAPI.patchDisplayName(value)
                statusMessage = String(localized: "account.profile.name-saved")
            } catch {
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }

    private func updateSharing(
        publicProfileEnabled: Bool? = nil,
        shareMode: PublicShareMode? = nil,
        allowRecipeDownloads: Bool? = nil
    ) async {
        guard !isLoading else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await AccountAPI.patchSharingSettings(
                publicProfileEnabled: publicProfileEnabled,
                shareMode: shareMode,
                allowRecipeDownloads: allowRecipeDownloads
            )
            if let enabled = response.publicProfileEnabled { self.publicProfileEnabled = enabled }
            if let mode = PublicShareMode(apiValue: response.shareMode) { self.shareMode = mode }
            if let allowed = response.allowRecipeDownloads { self.allowRecipeDownloads = allowed }
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func updateNutrition(_ value: Bool) async {
        do {
            try await AccountAPI.updateNutritionEnabled(value)
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func logout() async {
        do {
            try authService.logout()
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }
}

// MARK: - Shared Mac helpers

private struct MacRemoteThumbnail: View {
    let url: URL?
    let fallbackSymbol: String

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholder: some View {
        AppSymbol.image(fallbackSymbol)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Assistant

/// Lightweight native Mac chat surface. It shares the assistant REST/stream
/// protocol with iOS, but keeps the composer keyboard-first and avoids the
/// mobile voice/attachment chrome.
struct MacAssistantView: View {
    @Environment(YjsSyncService.self) private var syncService
    let contextRecipeId: String?

    @State private var threadId: String?
    @State private var messages: [AssistantMessage] = []
    @State private var input = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            let isUser = message.role == "user"
                            HStack {
                                if isUser { Spacer(minLength: 64) }
                                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                                    Text(
                                        message.text.isEmpty
                                            ? String(localized: "assistant.thinking")
                                            : message.text
                                    )
                                    .appBodySelectable(
                                        multilineTextAlignment: isUser ? .trailing : .leading
                                    )
                                    .padding(10)
                                    .background(
                                        isUser
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    MacAssistantMessageMetaRow(message: message, isUser: isUser)
                                }
                                if !isUser { Spacer(minLength: 64) }
                            }
                        }
                    }
                    .padding(16)
                }

                Divider()
                HStack(alignment: .bottom, spacing: 8) {
                    TextEditor(text: $input)
                        .font(AppTypography.body)
                        .frame(minHeight: 42, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.25))
                        }
                        .accessibilityIdentifier(AccessibilityIdentifiers.assistantMessageInput)
                    Button {
                        Task { await send() }
                    } label: {
                        AppSymbol.image("paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(Text("assistant.send"))
                    .accessibilityLabel(Text("assistant.send"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantSendButton)
                }
                .padding(12)

                if let errorMessage {
                    Text(errorMessage)
                        .appFootnote()
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier(AccessibilityIdentifiers.assistantOfflineFootnote)
                }
            }
            .navigationTitle(Text("assistant.title"))
            .toolbar {
                ToolbarItem {
                    Button {
                        streamTask?.cancel()
                        threadId = nil
                        messages = []
                    } label: {
                        AppSymbol.image("plus")
                    }
                    .help(Text("assistant.new-chat"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantNewThreadButton)
                }
            }
            .task {
                if !syncService.connectionState.isConnected {
                    errorMessage = String(localized: "assistant.offline.description")
                }
            }
            .onDisappear {
                streamTask?.cancel()
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantSheet)
    }

    private func send() async {
        guard !isSending else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        errorMessage = nil
        input = ""

        do {
            if threadId == nil {
                threadId = try await AssistantAPI.createThread(
                    language: AppLanguagePreference.current.rawValue
                ).id
            }
            guard let threadId else { return }
            let userId = "mac-user-\(UUID().uuidString)"
            messages.append(
                AssistantMessage(
                    id: userId,
                    role: "user",
                    text: text,
                    isStreaming: false,
                    metadata: nil,
                    createdAt: Date()
                )
            )
            let assistantId = "mac-assistant-\(UUID().uuidString)"
            messages.append(
                AssistantMessage(
                    id: assistantId,
                    role: "assistant",
                    text: "",
                    isStreaming: true,
                    metadata: nil,
                    createdAt: Date()
                )
            )
            let attachments = contextRecipeId.map { [$0] } ?? []
            streamTask = Task {
                do {
                    let stream = try await AssistantAPI.stream(
                        threadId: threadId,
                        message: text,
                        attachedRecipeIds: attachments,
                        language: AppLanguagePreference.current.rawValue
                    )
                    for try await event in stream {
                        guard !Task.isCancelled else { return }
                        switch event {
                        case .textDelta(let delta):
                            updateAssistantMessage(id: assistantId) { $0.text += delta }
                        case .final(let final):
                            if let content = final.assistantMessage?.content {
                                updateAssistantMessage(id: assistantId) {
                                    $0.text = content
                                    $0.isStreaming = false
                                    $0.metadata = final.assistantMessage?.metadata
                                }
                            } else {
                                updateAssistantMessage(id: assistantId) { $0.isStreaming = false }
                            }
                        case .error:
                            errorMessage = String(localized: "assistant.error-unavailable")
                            updateAssistantMessage(id: assistantId) { $0.isStreaming = false }
                        case .textStart, .toolStart:
                            break
                        }
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = UserFacingAPIError.message(for: error)
                        updateAssistantMessage(id: assistantId) { $0.isStreaming = false }
                    }
                }
            }
            await streamTask?.value
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
        isSending = false
    }

    private func updateAssistantMessage(
        id: String,
        _ update: (inout AssistantMessage) -> Void
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        update(&messages[index])
    }
}

/// Pointer-profile metadata for a Mac assistant message.
///
/// The controls stay keyboard/context-menu reachable while remaining visually
/// quiet until the pointer enters the message footer. This mirrors the web
/// affordance without making the Mac transcript permanently noisy.
private struct MacAssistantMessageMetaRow: View {
    let message: AssistantMessage
    let isUser: Bool

    @Environment(\.locale) private var locale
    @State private var isHovered = false
    @State private var isCopied = false
    @FocusState private var isFocused: Bool

    private var copyText: String {
        message.text
    }

    private var canCopy: Bool {
        !copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var formattedTimestamp: String {
        MacAssistantMessageTimestampFormatter.format(createdAt: message.createdAt, locale: locale)
    }

    private var showControls: Bool {
        isHovered || isFocused
    }

    var body: some View {
        HStack(spacing: 6) {
            if isUser {
                if canCopy { copyButton }
                timestampLabel
            } else {
                timestampLabel
                if canCopy { copyButton }
            }
        }
        .padding(.horizontal, isUser ? 4 : 0)
        .frame(minHeight: 28)
        .opacity(showControls ? 1 : 0.001)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .focusable()
        .focused($isFocused)
        .contextMenu {
            if canCopy {
                Button {
                    copyToPasteboard()
                } label: {
                    Label("assistant.copy-message", systemImage: "doc.on.doc")
                }
            }
            Text(formattedTimestamp)
        }
        .accessibilityElement(children: .contain)
    }

    private var timestampLabel: some View {
        Text(formattedTimestamp)
            .appFootnote()
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(formattedTimestamp))
    }

    private var copyButton: some View {
        Button(action: copyToPasteboard) {
            ZStack {
                AppSymbol.image("doc.on.doc")
                    .opacity(isCopied ? 0 : 1)
                AppSymbol.image("checkmark.circle")
                    .opacity(isCopied ? 1 : 0)
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("assistant.copy-message"))
        .accessibilityLabel(Text("assistant.copy-message"))
        .accessibilityIdentifier("assistant_message_copy_button_\(message.id)")
    }

    private func copyToPasteboard() {
        guard canCopy else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText, forType: .string)
        isCopied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isCopied = false
        }
    }
}

private enum MacAssistantMessageTimestampFormatter {
    static func format(createdAt: Date, locale: Locale) -> String {
        let calendar = Calendar.current
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        if calendar.isDate(createdAt, inSameDayAs: now) {
            return timeFormatter.string(from: createdAt)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(createdAt, inSameDayAs: yesterday) {
            return "\(Bundle.currentLocalizedString("assistant.timestamp.yesterday")), \(timeFormatter.string(from: createdAt))"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.component(.year, from: createdAt) == calendar.component(.year, from: now)
                ? "MMMdHHmm"
                : "MMMdyyyy"
        )
        return formatter.string(from: createdAt)
    }
}
