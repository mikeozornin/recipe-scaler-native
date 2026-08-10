import SwiftUI
import AppKit
import RecipeScalerCore

/// Renders emoji with Apple Color Emoji. Martian must never paint emoji glyphs.
private struct MacEmojiText: View {
    let emoji: String
    var size: CGFloat

    var body: some View {
        Text(emoji)
            .font(.system(size: size))
            .fixedSize()
    }
}

/// First macOS detail slice: read-only Y.Doc-backed recipe content plus the
/// shared recipe mutations exposed in the regular toolbar.
struct MacRecipeDetailView: View {
    let recipeId: String
    var onDeleted: () -> Void = {}

    @Environment(YjsSyncService.self) private var syncService
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var ingredientsColumnWidth = CGFloat(LayoutPreferencesStore.recipeIngredientsWidthDefault)
    @State private var showingAssignSheet = false
    @State private var showingDeleteConfirmation = false

    private static let wideDetailThreshold: CGFloat = 640

    private var recipe: RecipeData? {
        guard syncService.currentRecipe?.id == recipeId else { return nil }
        return syncService.currentRecipe
    }

    private var isPinned: Bool {
        syncService.collectionEntries.first { $0.id == recipeId }?.isPinned ?? false
    }

    /// `imageUrl` from the loaded doc, falling back to the collection entry so
    /// the hero renders immediately before the full Y.Doc arrives (iOS parity).
    private var headerImageUrl: String? {
        if let recipeUrl = recipe?.imageUrl, !recipeUrl.isEmpty { return recipeUrl }
        if let entryUrl = syncService.collectionEntries.first(where: { $0.id == recipeId })?.imageUrl,
           !entryUrl.isEmpty {
            return entryUrl
        }
        return nil
    }

    private var allowsImageNetworkRefresh: Bool {
        syncService.connectionState == .connected
    }

    var body: some View {
        Group {
            if let recipe {
                recipeContent(recipe)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    AppEmptyState.label("shell.recipe-split.select-recipe.title", symbol: "book")
                } description: {
                    Text(errorMessage ?? "recipe.detail.not-found")
                        .appBody()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        togglePin()
                    } label: {
                        Label(
                            isPinned ? "recipe.list.unpin" : "recipe.list.pin",
                            systemImage: isPinned ? "pin.slash" : "pin"
                        )
                    }
                    Button {
                        showingAssignSheet = true
                    } label: {
                        Label("collections.assign-title", systemImage: "folder.badge.plus")
                    }
                    .disabled(recipe == nil)
                    Button {
                        addToShopping()
                    } label: {
                        Label("shopping.detail-add-all", systemImage: "cart.badge.plus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("recipe.list.delete", systemImage: "trash")
                    }
                } label: {
                    AppToolbarStyle.iconOnly(systemName: "ellipsis.circle")
                }
                .appToolbarIconButton()
                .accessibilityLabel(Text("recipe.detail.actions"))
                .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailActions)
            }
        }
        .sheet(isPresented: $showingAssignSheet) {
            if let recipe {
                MacCollectionAssignSheet(
                    recipeId: recipe.id,
                    recipeName: RecipeTitleEmoji.displayName(for: recipe.name)
                )
                .frame(minWidth: 360, minHeight: 320)
            }
        }
        .alert(
            Bundle.currentLocalizedString("recipe.list.delete.confirm.title"),
            isPresented: $showingDeleteConfirmation
        ) {
            Button(
                Bundle.currentLocalizedString("recipe.list.delete.confirm.action"),
                role: .destructive
            ) {
                deleteRecipe()
            }
            Button(
                Bundle.currentLocalizedString("recipe.list.delete.confirm.cancel"),
                role: .cancel
            ) { }
        } message: {
            Text(
                String(
                    format: Bundle.currentLocalizedString("recipe.list.delete.confirm.message"),
                    locale: .current,
                    recipe.map { RecipeTitleEmoji.displayName(for: $0.name) } ?? ""
                )
            )
        }
        .task(id: recipeId) {
            isLoading = true
            errorMessage = nil
            await syncService.loadRecipe(recipeId: recipeId)
            isLoading = false
            if syncService.currentRecipe?.id != recipeId {
                errorMessage = String(localized: "recipe.detail.not-found")
            }
        }
    }

    @ViewBuilder
    private func recipeContent(_ recipe: RecipeData) -> some View {
        GeometryReader { proxy in
            if proxy.size.width >= Self.wideDetailThreshold {
                wideRecipeContent(recipe)
            } else {
                narrowRecipeContent(recipe)
            }
        }
        .onAppear {
            ingredientsColumnWidth = CGFloat(LayoutPreferencesStore.recipeIngredientsWidth)
        }
    }

    private func narrowRecipeContent(_ recipe: RecipeData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                recipeHeader(recipe)
                ingredientsSection(recipe)
                instructionsSection(recipe)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func wideRecipeContent(_ recipe: RecipeData) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            recipeHeader(recipe)

            HSplitView {
                ScrollView {
                    ingredientsSection(recipe)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 20)
                }
                .frame(
                    minWidth: CGFloat(LayoutPreferencesStore.recipeIngredientsWidthMin),
                    idealWidth: ingredientsColumnWidth,
                    maxWidth: CGFloat(LayoutPreferencesStore.recipeIngredientsWidthMax)
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MacRecipeIngredientsWidthPreferenceKey.self,
                            value: proxy.size.width
                        )
                    }
                }

                ScrollView {
                    instructionsSection(recipe)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                }
                .frame(minWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(MacRecipeIngredientsWidthPreferenceKey.self) { width in
                guard width > 0 else { return }
                let clampedWidth = Swift.min(
                    Swift.max(width, CGFloat(LayoutPreferencesStore.recipeIngredientsWidthMin)),
                    CGFloat(LayoutPreferencesStore.recipeIngredientsWidthMax)
                )
                guard abs(ingredientsColumnWidth - clampedWidth) > 1 else { return }
                ingredientsColumnWidth = clampedWidth
                LayoutPreferencesStore.recipeIngredientsWidth = Double(clampedWidth.rounded())
            }
        }
        .padding(32)
    }

    @ViewBuilder
    private func recipeHeader(_ recipe: RecipeData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let imageUrl = headerImageUrl, !imageUrl.isEmpty {
                MacRecipeHeroImage(
                    recipeId: recipeId,
                    imageUrl: imageUrl,
                    imageAspectRatio: recipe.imageAspectRatio.map { CGFloat($0) },
                    allowsNetworkRefresh: allowsImageNetworkRefresh
                )
            }

            if isEditingTitle {
                HStack(spacing: 8) {
                    TextField("recipe.title", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)
                        .appBodyFieldTypography()
                    Button("common.save") {
                        saveTitle()
                    }
                    .appToolbarTextButton()
                    Button("common.cancel") {
                        isEditingTitle = false
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let leadingEmoji = RecipeTitleEmoji.leadingEmoji(in: recipe.name) {
                        MacEmojiText(emoji: leadingEmoji, size: AppTypography.recipeTitleSize)
                    }
                    Text(RecipeTitleEmoji.displayName(for: recipe.name))
                        .font(AppTypography.display(AppTypography.recipeTitleSize))
                        .textSelection(.enabled)
                    Button {
                        titleDraft = RecipeTitleEmoji.displayName(for: recipe.name)
                        isEditingTitle = true
                    } label: {
                        AppSymbol.image("pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("edit.edit"))
                    .accessibilityLabel(Text("edit.edit"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailTitleEdit)
                }
            }
        }
    }

    @ViewBuilder
    private func ingredientsSection(_ recipe: RecipeData) -> some View {
        if !recipe.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("recipe.ingredients")
                    .appHeadline()
                    .padding(.bottom, 8)

                ForEach(Array(recipe.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                    if index > 0 {
                        Divider()
                    }

                    if ingredient.isHeaderRow {
                        ingredientHeaderRow(ingredient.name)
                    } else {
                        ingredientRow(ingredient)
                    }
                }
            }
        }
    }

    private func ingredientHeaderRow(_ name: String) -> some View {
        Text(name)
            .font(AppTypography.sansMedium(AppTypography.bodySize))
            .textCase(.uppercase)
            .tracking(AppTypography.bodySize * 0.02)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func ingredientRow(_ ingredient: IngredientData) -> some View {
        HStack(alignment: .center, spacing: 4) {
            HStack(alignment: .center, spacing: 2) {
                MacIngredientIllustration(illustrationId: ingredient.illustrationId)
                Text(ingredient.name)
                    .appBody()
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if ingredient.hasQuantity {
                Text(quantityDisplay(for: ingredient))
                    .font(AppTypography.mono(AppTypography.bodySize))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Matches iOS/web rhythm: `quantity` (or `quantity unit` when unit present).
    /// Empty for section headers / `hasQuantity == false`.
    private func quantityDisplay(for ingredient: IngredientData) -> String {
        let quantity = ingredient.quantityText
        let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if unit.isEmpty {
            return quantity
        }
        return "\(quantity) \(unit)"
    }

    @ViewBuilder
    private func instructionsSection(_ recipe: RecipeData) -> some View {
        if let description = recipe.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("recipe.instructions")
                    .appHeadline()
                MacRecipeDescriptionView(
                    htmlContent: description,
                    recipeId: recipeId,
                    recipeDisplayName: RecipeTitleEmoji.displayName(for: recipe.name)
                )
            }
        }
    }

    private func saveTitle() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            do {
                try await syncService.updateRecipeName(title)
                isEditingTitle = false
            } catch {
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }

    private func togglePin() {
        Task {
            do {
                try await syncService.setRecipePinned(recipeId: recipeId, isPinned: !isPinned)
            } catch {
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }

    private func addToShopping() {
        Task {
            do {
                _ = try await syncService.addWholeRecipeToShoppingList(recipeId: recipeId)
            } catch {
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }

    private func deleteRecipe() {
        Task {
            do {
                try await syncService.deleteRecipeFromCollection(recipeId: recipeId)
                onDeleted()
            } catch {
                errorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }
}

private struct MacRecipeIngredientsWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Hero image

/// macOS recipe hero. The iOS path uses `RecipeDetailImageSection` /
/// `RecipeCachedImageView` (both UIKit-bound), which are not part of the
/// `RecipeScalerMac` target. This equivalent shares the same on-disk image
/// cache (`RecipeImageService` / `RecipeImageDiskCache`) for offline display
/// and falls back to `AsyncImage` for the cold-start network path.
private struct MacRecipeHeroImage: View {
    let recipeId: String
    let imageUrl: String
    let imageAspectRatio: CGFloat?
    let allowsNetworkRefresh: Bool

    @State private var nsImage: NSImage?

    private var aspectRatio: CGFloat {
        if let imageAspectRatio, imageAspectRatio > 0 { return imageAspectRatio }
        if let size = nsImage?.size, size.height > 0 { return size.width / size.height }
        return 4.0 / 3.0
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else if let remote = remoteImageURL {
                AsyncImage(url: remote) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fill)
        .frame(maxHeight: 400)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: loadTaskKey) {
            await reload()
        }
        .onChange(of: allowsNetworkRefresh) { wasAllowed, isAllowed in
            guard !wasAllowed, isAllowed else { return }
            Task { await reload() }
        }
    }

    private var loadTaskKey: String {
        "\(recipeId)|\(imageUrl)|\(allowsNetworkRefresh)"
    }

    private var remoteImageURL: URL? {
        guard let version = RecipeImageVersion.token(from: imageUrl) else { return nil }
        var components = URLComponents(string: "\(Config.baseURL)/api/recipes/\(recipeId)/image")
        components?.queryItems = [
            URLQueryItem(name: "preview", value: "false"),
            URLQueryItem(name: "version", value: version)
        ]
        return components?.url
    }

    private func reload() async {
        if let fileURL = RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .full) {
            await apply(from: fileURL)
        }
        guard allowsNetworkRefresh else { return }
        if let fileURL = await RecipeImageService.shared.ensureCached(
            recipeId: recipeId,
            imageUrl: imageUrl,
            variant: .full,
            allowNetwork: true
        ) {
            await apply(from: fileURL)
        } else if nsImage == nil {
            await MainActor.run { nsImage = nil }
        }
    }

    private func apply(from fileURL: URL) async {
        let decoded = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: fileURL)
        }.value
        guard let decoded else { return }
        await MainActor.run { nsImage = decoded }
    }
}

// MARK: - Ingredient illustration

/// macOS ingredient thumb. Reuses the shared `IngredientIllustrationCatalog`
/// (Core, platform-agnostic) for id validation and the same layout metrics as
/// iOS. The bundled `.webp` assets live in the app bundle and are decoded into
/// `NSImage` here, mirroring the UIKit-bound `IngredientIllustrationThumb` /
/// `IngredientIllustrationImageStore` pair that is excluded from the Mac target.
private struct MacIngredientIllustration: View {
    let illustrationId: String?

    private static let imageCache = NSCache<NSString, NSImage>()

    private var resolvedId: String? {
        guard let raw = illustrationId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              IngredientIllustrationCatalog.shared.contains(id: raw) else {
            return nil
        }
        return raw
    }

    var body: some View {
        ZStack {
            if let resolvedId, let nsImage = Self.cachedImage(for: resolvedId) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                MacIngredientBowlPlaceholder(size: 22)
            }
        }
        .frame(
            width: IngredientIllustrationLayoutMetrics.displaySlotPt,
            height: IngredientIllustrationLayoutMetrics.displaySlotPt
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: IngredientIllustrationLayoutMetrics.cornerRadiusPt,
                style: .continuous
            )
        )
        .accessibilityHidden(true)
    }

    private static func cachedImage(for illustrationId: String) -> NSImage? {
        let key = illustrationId as NSString
        if let hit = imageCache.object(forKey: key) {
            return hit
        }
        guard let url = Bundle.main.url(
            forResource: illustrationId,
            withExtension: "webp",
            subdirectory: "IngredientIllustrations"
        ),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        imageCache.setObject(image, forKey: key)
        return image
    }
}

/// Mac-scoped equivalent of the iOS `IngredientBowlIcon` (Canvas-only, no
/// UIKit). Drawn locally because `IngredientBowlIcon.swift` is excluded from
/// the `RecipeScalerMac` target.
private struct MacIngredientBowlPlaceholder: View {
    var size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let stroke = Color.secondary
            let lineWidth: CGFloat = 1.5
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let bowlW = size * 0.85
            let bowlH = size * 0.35
            let bowlRect = CGRect(
                x: cx - bowlW / 2,
                y: cy - bowlH * 0.2,
                width: bowlW,
                height: bowlH
            )
            var bowl = Path()
            bowl.addEllipse(in: bowlRect)
            context.stroke(bowl, with: .color(stroke), lineWidth: lineWidth)

            var steam = Path()
            let steamY = bowlRect.minY - size * 0.12
            steam.move(to: CGPoint(x: cx - size * 0.15, y: steamY + size * 0.08))
            steam.addQuadCurve(
                to: CGPoint(x: cx - size * 0.15, y: steamY - size * 0.05),
                control: CGPoint(x: cx - size * 0.28, y: steamY)
            )
            steam.move(to: CGPoint(x: cx, y: steamY + size * 0.1))
            steam.addQuadCurve(
                to: CGPoint(x: cx, y: steamY - size * 0.08),
                control: CGPoint(x: cx + size * 0.12, y: steamY + size * 0.02)
            )
            context.stroke(steam, with: .color(stroke), lineWidth: lineWidth)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
