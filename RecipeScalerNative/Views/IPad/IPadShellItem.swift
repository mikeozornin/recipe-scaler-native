import SwiftUI

/// What the iPad `TabView` selects (spec 081, plan.md Р2): a section, or a user
/// collection row of the sidebar. Never stored: it is read from and written to
/// `AppShellCoordinator.selectedTab` and `recipesPath`, so there is no second source of truth.
enum IPadShellItem: Hashable {
    case tab(AppTab)
    case collection(String)
}

/// The computed `IPadShellItem` selection over the coordinator.
@MainActor
struct IPadShellSelection {
    let coordinator: AppShellCoordinator
    /// The tab bar is the sidebar (`\.tabBarPlacement == .sidebar`). In the top bar and in
    /// compact a selected collection reads as `.tab(.recipes)`: a selected collection `Tab`
    /// would pull the whole «Коллекции» group into the top bar (spike S1, workaround 4).
    var sidebarShown: Bool
    /// The Recipes section is drawn by `IPadRecipesSplitView` (T024). In US1, in compact and
    /// on the phone stack it is `false`: a collection opens its phone screen.
    var isSplitActive = false
    /// Active user collections, i.e. the sidebar rows. Virtual folders are not among them.
    var collectionIds: Set<String>
    /// First recipe of a collection as its list shows it; asked only while `isSplitActive`.
    var firstRecipeId: (String) -> String? = { _ in nil }
    /// In `.padRegular` «Профиль» opens the profile sheet and keeps the selection (plan.md Р2a).
    var layoutMode: AppLayoutMode = .phone

    var item: IPadShellItem {
        Self.item(
            selectedTab: coordinator.selectedTab,
            recipesPath: coordinator.recipesPath,
            sidebarShown: sidebarShown,
            collectionIds: collectionIds
        )
    }

    var binding: Binding<IPadShellItem> {
        Binding(get: { item }, set: { select($0) })
    }

    func select(_ newItem: IPadShellItem) {
        switch newItem {
        case .tab(.profile) where layoutMode == .padRegular:
            coordinator.presentProfileSheet()
        case .tab(let tab):
            // «Ассистент» keeps the selection (pending open, as on the iPhone);
            // a second tap on the current section pops it to the root.
            coordinator.handleTabSelection(tab)
        case .collection(let collectionId):
            if isSplitActive, item == newItem { return }
            coordinator.selectedTab = .recipes
            coordinator.recipesPath = Self.recipesPath(
                forCollection: collectionId,
                isSplitActive: isSplitActive,
                firstRecipeId: isSplitActive ? firstRecipeId(collectionId) : nil
            )
        }
    }

    /// `.collection(id)` only in the sidebar, on Recipes, when the last `.folder` of the
    /// path is a user collection; otherwise the selected section.
    static func item(
        selectedTab: AppTab,
        recipesPath: [RecipesRoute],
        sidebarShown: Bool,
        collectionIds: Set<String>
    ) -> IPadShellItem {
        guard sidebarShown, selectedTab == .recipes,
              let collectionId = RecipesSelection.selection(from: recipesPath).collectionId,
              collectionIds.contains(collectionId) else {
            return .tab(selectedTab)
        }
        return .collection(collectionId)
    }

    /// Without the split: the phone collection screen. With it: the collection and its
    /// first recipe; an empty collection gives `[.folder(id)]`.
    static func recipesPath(
        forCollection collectionId: String,
        isSplitActive: Bool,
        firstRecipeId: String?
    ) -> [RecipesRoute] {
        guard isSplitActive else { return [.folder(collectionId)] }
        return RecipesSelection.selectingCollection(
            collectionId,
            firstRecipeId: firstRecipeId,
            folderContext: collectionId
        )
    }
}
