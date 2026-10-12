import RecipeScalerCore
import SwiftUI

/// The iPad shell on iPadOS 26.2+ (spec 081, plan.md Р2): one `.sidebarAdaptable`
/// `TabView` that is a sidebar, a top tab bar (sidebar hidden) or the phone bottom bar
/// (compact window). Tab roots are the phone ones (`AppShellTabRoots`).
///
/// System workarounds from the spike (S1, S3, S5):
/// - badges only while the tab bar is the sidebar, or they show up in the top bar;
/// - «Профиль» and «Ассистент» are `.pinned` icons of the top bar and hidden from the
///   sidebar only while it is shown (plain `.hidden` removes them from the top bar too);
/// - the «Коллекции» section exists only while the sidebar is shown: in compact
///   collections and «Ассистент» go to «Ещё»; in the top bar a collection that was
///   selected when the sidebar hid stays in the bar for good;
/// - a selected collection exists only in the sidebar (`IPadShellSelection`);
/// - no `.inspector` on the `TabView`: it zeroes the top safe area of the tabs.
///
/// Dependencies are passed in explicitly: labels are measured as bar items, where
/// iOS 26 may hand them a fallback environment (`@Environment(Observable)` traps).
@available(iOS 26.2, *)
struct IPadAdaptiveTabView: View {
    @Bindable var coordinator: AppShellCoordinator
    let syncService: YjsSyncService
    let feedBadgeStore: FeedBadgeStore
    let tabRoots: AppShellTabRoots

    @Environment(\.appLayoutMode) private var layoutMode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// `\.tabBarPlacement == .sidebar`, reported from the selected page.
    @State private var sidebarShown = false
    @State private var isNewCollectionAlertPresented = false
    @State private var newCollectionName = ""
    @State private var isSavingCollection = false

    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var collections: [RecipeFolder] {
        RecipeFolder.sortedActive(syncService.folders)
    }

    private func selection(collections: [RecipeFolder]) -> IPadShellSelection {
        IPadShellSelection(
            coordinator: coordinator,
            sidebarShown: sidebarShown && !isCompact,
            isSplitActive: layoutMode == .padRegular,
            collectionIds: Set(collections.map(\.id)),
            firstRecipeId: { syncService.collectionIndex.entries(inList: $0).first?.id },
            layoutMode: layoutMode,
            onNewCollection: presentNewCollectionAlert
        )
    }

    var body: some View {
        let collections = collections
        let selection = selection(collections: collections)
        let current = selection.item
        return TabView(selection: selection.binding) {
            Tab(value: IPadShellItem.tab(.discover)) {
                page(tabRoots.discover(showsAssistantToolbarButton: showsAssistantToolbarButton))
            } label: {
                FeedBadgeTabLabel(feedBadgeStore: feedBadgeStore)
            }

            Tab(value: IPadShellItem.tab(.recipes)) {
                // One Recipes root at a time: a selected collection row hosts it.
                if case .collection = current {
                    page(Color.clear)
                } else {
                    recipesPage()
                }
            } label: {
                AppTabBarLabel(tab: .recipes)
            }
            .badge(sidebarBadge(syncService.collectionIndex.live.count))

            Tab(value: IPadShellItem.tab(.shopping)) {
                page(tabRoots.shopping(showsAssistantToolbarButton: showsAssistantToolbarButton))
            } label: {
                AppTabBarLabel(tab: .shopping)
            }
            .badge(sidebarBadge(shoppingToBuyCount))

            Tab(value: IPadShellItem.tab(.profile)) {
                // In a wide window the profile is a form sheet (T019a), never a page;
                // a sheet kept up after narrowing is the only profile too.
                if layoutMode == .padRegular || coordinator.isProfileSheetPresented {
                    page(Color.clear)
                } else {
                    page(tabRoots.profile())
                }
            } label: {
                AppTabBarLabel(tab: .profile)
            }
            .tabPlacement(.pinned)
            .defaultVisibility(sidebarShown ? .hidden : .automatic, for: .sidebar)

            // Spec 074 — fake tab: opens the assistant sheet, never selected.
            Tab(value: IPadShellItem.tab(.assistant)) {
                page(Color.clear)
            } label: {
                AppTabBarLabel(tab: .assistant)
            }
            .tabPlacement(.pinned)
            .defaultVisibility(sidebarShown ? .hidden : .automatic, for: .sidebar)

            if sidebarShown && !isCompact {
                TabSection {
                    ForEach(collections, id: \.id) { folder in
                        let item = IPadShellItem.collection(folder.id)
                        let count = syncService.collectionIndex.countByFolder[folder.id] ?? 0
                        Tab(value: item) {
                            if current == item {
                                recipesPage()
                            } else {
                                page(Color.clear)
                            }
                        } label: {
                            collectionLabel(folder, count: count)
                        }
                        .badge(sidebarBadge(count))
                    }
                    if collections.isEmpty {
                        // A section without tabs is dropped with its header and action;
                        // a child hidden in the sidebar keeps both (iPadOS 26.3). Never
                        // shown, so never selected; `.newCollection` would only ask a name.
                        Tab(value: IPadShellItem.newCollection) {
                            page(Color.clear)
                        } label: {
                            Label("collections.new", systemImage: "plus")
                        }
                        .defaultVisibility(.hidden, for: .sidebar)
                    }
                } header: {
                    Text("collections.title")
                        .accessibilityIdentifier(AccessibilityIdentifiers.ipadSidebarCollections)
                }
                .sectionActions {
                    // iPadOS 26.3 drops identifiers of section actions and alert
                    // fields from the tree; UI tests fall back to the label.
                    Button(action: presentNewCollectionAlert) {
                        Label("collections.new", systemImage: "plus")
                            .accessibilityIdentifier(AccessibilityIdentifiers.ipadSidebarNewCollection)
                    }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarBottomBar {
            // Profile entry of the sidebar (plan.md Р2a); compact has no sidebar.
            if layoutMode == .padRegular {
                IPadSidebarProfileFooter(
                    coordinator: coordinator,
                    auth: tabRoots.authService,
                    syncService: syncService,
                    timer: tabRoots.timerManager,
                    vkusvillSettings: tabRoots.vkusvillSettings,
                    performLogoutTeardown: tabRoots.performLogoutTeardown
                )
            }
        }
        .alert("collections.new", isPresented: $isNewCollectionAlertPresented) {
            TextField("collections.new-placeholder", text: $newCollectionName)
                .accessibilityIdentifier(AccessibilityIdentifiers.ipadNewCollectionNameField)
            Button("common.cancel", role: .cancel) {
                newCollectionName = ""
            }
            Button("collections.create") {
                commitNewCollection()
            }
            .disabled(NewCollectionCommit.name(from: newCollectionName) == nil || isSavingCollection)
        }
        .task {
            await applyLaunchSidebarVisibility()
        }
        // «Развернуть» (T024) hides the sidebar; these keep that state honest.
        .onChange(of: sidebarShown) { _, shown in
            coordinator.noteSidebarShown(shown)
        }
        .onChange(of: layoutMode) { _, mode in
            if mode == .padRegular {
                coordinator.restoreSidebarHiddenByRecipeExpand(isPadRegular: true)
            } else {
                // Compact is the phone: no expanded recipe, the sidebar back once wide again.
                coordinator.setRecipeDetailExpanded(false, isPadRegular: false)
            }
        }
        .onChange(of: coordinator.selectedTab) { _, _ in
            coordinator.restoreSidebarHiddenByRecipeExpand(isPadRegular: layoutMode == .padRegular)
        }
        .modifier(IPadProfileSheetModifier(
            coordinator: coordinator,
            auth: tabRoots.authService,
            timer: tabRoots.timerManager,
            vkusvillSettings: tabRoots.vkusvillSettings,
            performLogoutTeardown: tabRoots.performLogoutTeardown
        ))
    }

    private func presentNewCollectionAlert() {
        newCollectionName = ""
        isNewCollectionAlertPresented = true
    }

    /// The same commit as the phone collections list (`NewCollectionCommit`).
    private func commitNewCollection() {
        defer { newCollectionName = "" }
        guard let name = NewCollectionCommit.name(from: newCollectionName) else { return }
        NewCollectionCommit.start(name, isSaving: $isSavingCollection, syncService: syncService)
    }

    /// Every page reports the tab bar placement; only the selected one is on screen.
    private func page<Content: View>(_ content: Content) -> some View {
        content.reportsIPadSidebarShown($sidebarShown)
    }

    /// `.padRegular`: the list column and the recipe panel (T024); the title of the column
    /// is the collection menu while the tab bar is the top bar. Else the phone stack.
    @ViewBuilder
    private func recipesPage() -> some View {
        if layoutMode == .padRegular {
            page(tabRoots.recipesSplit(
                showsCollectionMenu: !sidebarShown,
                showsAssistantToolbarButton: showsAssistantToolbarButton
            ))
        } else {
            page(tabRoots.recipes())
        }
    }

    /// ✦ in the page toolbars only while the sidebar hides the pinned «Ассистент» tab:
    /// one assistant entry on screen (`IPadLayoutPolicy.showsAssistantToolbarButton`).
    private var showsAssistantToolbarButton: Bool {
        IPadLayoutPolicy.showsAssistantToolbarButton(
            layoutMode: layoutMode,
            tabBarIsSidebar: sidebarShown && !isCompact
        )
    }

    private func sidebarBadge(_ count: Int) -> Int {
        sidebarShown ? count : 0
    }

    /// Items still to buy, from the shopping document loaded with the session.
    private var shoppingToBuyCount: Int {
        syncService.shoppingSnapshot.items.reduce(0) { $0 + ($1.purchased ? 0 : 1) }
    }

    /// A row as the phone collections list draws it (`CollectionsRootView.collectionRow`):
    /// the collection's emoji as the icon, else its folder in the collection colour, then
    /// the name; the count is the row badge.
    ///
    /// A tab label is only an image and a title, so the emoji is drawn into the icon
    /// (`IPadSidebarCollectionIcon`) and never joins the title. The folder is drawn in its
    /// own colour: the sidebar tints a template symbol black.
    private func collectionLabel(_ folder: RecipeFolder, count: Int) -> some View {
        let presentation = FolderDisplayName.presentation(forStoredName: folder.name)
        let icon = IPadSidebarCollectionIcon.image(
            emoji: presentation.leadingEmoji,
            symbolName: RecipeFolderConstants.folderIconName(recipeCount: count),
            tint: UIColor(RecipeAccentColor.folderIconColor(folderId: folder.id, folder: folder))
        )
        return Label {
            Text(presentation.displayName)
        } icon: {
            Image(uiImage: icon)
                .renderingMode(.original)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.ipadSidebarCollection(folderId: folder.id))
    }

    /// DEBUG `-IPadSidebarHidden=1` (layout.md `#recipes/tabs`): start without the sidebar.
    /// DEBUG `-IPadSidebarShown=1` (`#recipes/sidebar`): start with it, also in portrait.
    private func applyLaunchSidebarVisibility() async {
        let hidden = DebugLaunchOptions.iPadSidebarHidden
        guard hidden || DebugLaunchOptions.iPadSidebarShown, layoutMode == .padRegular else { return }
        // The `UITabBarController` is attached after the first layout pass.
        try? await Task.sleep(for: .milliseconds(300))
        IPadSidebarControl.setSidebarHidden(hidden)
    }
}

/// Sidebar collection icons as images in their own colours: a tab label is only an image
/// and a title, so the emoji the phone row shows as text is drawn into the image.
@MainActor
private enum IPadSidebarCollectionIcon {
    /// The emoji box: as wide as the sidebar's symbol slot, so the emoji is centred on the
    /// section icons and the name starts where theirs do. The emoji is drawn at the row
    /// text size.
    private static let canvas = CGSize(width: 28, height: 24)
    private static var emojiCache: [String: UIImage] = [:]

    static func image(emoji: String?, symbolName: String, tint: UIColor) -> UIImage {
        if let emoji {
            return emojiImage(emoji)
        }
        let configuration = UIImage.SymbolConfiguration(pointSize: AppTypography.bodySize, weight: .semibold)
        let symbol = UIImage(systemName: symbolName, withConfiguration: configuration) ?? UIImage()
        return symbol.withTintColor(tint, renderingMode: .alwaysOriginal)
    }

    private static func emojiImage(_ emoji: String) -> UIImage {
        if let cached = emojiCache[emoji] {
            return cached
        }
        // The system font falls back to Apple Color Emoji.
        let text = NSAttributedString(
            string: emoji,
            attributes: [.font: UIFont.systemFont(ofSize: AppTypography.bodySize + 2)]
        )
        let size = text.size()
        // A sequence wider than the box shrinks to fit instead of being clipped.
        let scale = min(1, canvas.width / max(size.width, 1), canvas.height / max(size.height, 1))
        let image = UIGraphicsImageRenderer(size: canvas).image { context in
            context.cgContext.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            context.cgContext.scaleBy(x: scale, y: scale)
            text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        }
        .withRenderingMode(.alwaysOriginal)
        emojiCache[emoji] = image
        return image
    }
}
