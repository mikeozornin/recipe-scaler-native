import SwiftUI

/// Spec 081 (US6, T045) — what the iPad menu bar and its shortcuts do in the scene.
/// Published by `AppShellView` (`focusedSceneValue(\.appCommands)`) only on the iPad,
/// so the iPhone with a keyboard gets no new shortcuts. Every action is a path the
/// phone already has; `nil` greys the item out.
///
/// Equal when the same items are available for the same `layoutMode`, the only value the
/// closures keep from the view that made them. Every body makes new closures; a value
/// SwiftUI could not compare went through the scene's focus on each layout, and rotating
/// the iPad into a compact window mid-edit hung the app in that loop.
struct AppCommandActions: Equatable {
    var layoutMode: AppLayoutMode
    /// ⌘1–⌘4. In a wide window «Профиль» opens the «Моё всё» sheet (FR-004a).
    var selectTab: (AppTab) -> Void
    /// ⌘J: the «Ассистент» tab (panel or sheet), or closes the open assistant.
    var toggleAssistant: () -> Void
    /// ⌘N: «Новый рецепт» of the list «+». `nil` during a recipe edit.
    var newRecipe: (() -> Void)?
    /// ⇧⌘I: the import sheet.
    var importRecipe: (() -> Void)?
    /// ⇧⌘N: the «Новая коллекция» alert of the iPad shell. `nil` before iPadOS 26.2.
    var newCollection: (() -> Void)?
    /// ⌘F: «Рецепты» with the focus in the search field. `nil` during a recipe edit.
    var focusSearch: (() -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.layoutMode == rhs.layoutMode && lhs.availableItems == rhs.availableItems
    }

    private var availableItems: [Bool] {
        [newRecipe, importRecipe, newCollection, focusSearch].map { $0 != nil }
    }
}

/// Spec 081 (US6, T045) — the open recipe for the «Рецепт» menu, published by
/// `YDocRecipeDetailView` on the iPad while it is on screen. No recipe, no menu: every
/// item is greyed out. During an edit only «Готово» is left, as in the phone toolbar.
///
/// Equal for the same recipe, flags and available items, as `AppCommandActions`: the
/// closures read the recipe and the servings when they run, not when they were made.
struct RecipeCommandActions: Equatable {
    var recipeId: String
    /// ⌘E: «Изменить».
    var edit: (() -> Void)?
    /// ⌘↩: «Готово» of the edit, the shortcut of the menu item (one owner per shortcut).
    /// XCUITest cannot press it on the simulator: `scripts/verify-ipad-keyboard.sh` sends it.
    var finishEdit: (() -> Void)?
    /// ⌘+ / ⌘− / ⌘0: the servings stepper; `nil` where its button is disabled.
    var increaseServings: (() -> Void)?
    var decreaseServings: (() -> Void)?
    var resetServings: (() -> Void)?
    /// ⇧⌘L: «В список покупок» of «…».
    var addToShopping: (() -> Void)?
    var isPinned: Bool
    /// ⇧⌘P: «Закрепить» / «Открепить» of «…».
    var togglePin: (() -> Void)?
    /// «В коллекцию…»: the popover (wide) or sheet of «…».
    var assignToCollections: (() -> Void)?
    var isScreenAwake: Bool
    /// ⌃⌘A: «Не гасить экран».
    var toggleScreenAwake: (() -> Void)?
    /// ⌘⌫: the phone's delete confirmation. A focused text field keeps ⌘⌫ for its text.
    var delete: (() -> Void)?
    /// «Поделиться рецептом…»: `RecipeShareSheet`.
    var share: (() -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.recipeId == rhs.recipeId
            && lhs.isPinned == rhs.isPinned
            && lhs.isScreenAwake == rhs.isScreenAwake
            && lhs.availableItems == rhs.availableItems
    }

    private var availableItems: [Bool] {
        [
            edit, finishEdit, increaseServings, decreaseServings, resetServings, addToShopping,
            togglePin, assignToCollections, toggleScreenAwake, delete, share,
        ].map { $0 != nil }
    }
}

private struct AppCommandActionsKey: FocusedValueKey {
    typealias Value = AppCommandActions
}

private struct RecipeCommandActionsKey: FocusedValueKey {
    typealias Value = RecipeCommandActions
}

extension FocusedValues {
    var appCommands: AppCommandActions? {
        get { self[AppCommandActionsKey.self] }
        set { self[AppCommandActionsKey.self] = newValue }
    }

    var recipeCommands: RecipeCommandActions? {
        get { self[RecipeCommandActionsKey.self] }
        set { self[RecipeCommandActionsKey.self] = newValue }
    }
}

/// Spec 081 (US6, T046; layout.md §Меню) — «Файл», «Рецепт» and «Вид» of the iPadOS menu
/// bar; the same shortcuts show while ⌘ is held. Only actions the iPhone has (Q3): no
/// «Экспорт в PDF…». Added to the `WindowGroup` on the iPad only.
///
/// Titles come from `Bundle.currentLocalizedString`: commands live outside `ContentView`
/// and its in-app language environment.
struct IPadMenuCommands: Commands {
    @FocusedValue(\.appCommands) private var app
    @FocusedValue(\.recipeCommands) private var recipe

    var body: some Commands {
        // The app has one window (FR-031): the group holds no system «Новое окно».
        CommandGroup(replacing: .newItem) {
            item("recipe.create.new", app?.newRecipe)
                .keyboardShortcut("n", modifiers: .command)
            item("ipad.menu.file.import", app?.importRecipe)
                .keyboardShortcut("i", modifiers: [.command, .shift])
            item("collections.new", app?.newCollection)
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            item("ipad.menu.file.share", recipe?.share)
        }

        CommandMenu(Self.title("ipad.menu.recipe")) {
            item("edit.edit", recipe?.edit)
                .keyboardShortcut("e", modifiers: .command)
            item("edit.done", recipe?.finishEdit)
                .keyboardShortcut(.return, modifiers: .command)
            Divider()
            item("ipad.menu.recipe.more-servings", recipe?.increaseServings)
                .keyboardShortcut("+", modifiers: .command)
            item("ipad.menu.recipe.fewer-servings", recipe?.decreaseServings)
                .keyboardShortcut("-", modifiers: .command)
            item("ipad.menu.recipe.original-servings", recipe?.resetServings)
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            item("shopping.detail-add-all", recipe?.addToShopping)
                .keyboardShortcut("l", modifiers: [.command, .shift])
            item(recipe?.isPinned == true ? "recipe.list.unpin" : "recipe.list.pin", recipe?.togglePin)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            item("ipad.menu.recipe.add-to-collection", recipe?.assignToCollections)
            // Not an `item()`: a toggle shows its checkmark. A held ⌃⌘A still must not
            // flip it on every key repeat.
            Toggle(Self.title("common.enable-wake-lock"), isOn: screenAwakeBinding)
                .disabled(recipe?.toggleScreenAwake == nil)
                .buttonRepeatBehavior(.disabled)
                .keyboardShortcut("a", modifiers: [.command, .control])
            Divider()
            item("recipe.list.delete", recipe?.delete)
                .keyboardShortcut(.delete, modifiers: .command)
        }

        // ⌃⌘S is the system «Show Sidebar» of the `.sidebar` group: it drives the
        // `.sidebarAdaptable` sidebar. A second ⌃⌘S item makes UIKit throw at launch.
        CommandGroup(before: .sidebar) {
            item("assistant.title", app?.toggleAssistant)
                .keyboardShortcut("j", modifiers: .command)
            Divider()
            tabItem(.discover, shortcut: "1")
            tabItem(.recipes, shortcut: "2")
            tabItem(.shopping, shortcut: "3")
            tabItem(.profile, shortcut: "4")
            Divider()
            if #available(iOS 18.0, *) {
                // `.searchFocused` needs iOS 18; before it the item does not exist.
                item("ipad.menu.view.find-recipe", app?.focusSearch)
                    .keyboardShortcut("f", modifiers: .command)
            }
            Divider()
        }
    }

    private var screenAwakeBinding: Binding<Bool> {
        Binding(
            get: { recipe?.isScreenAwake ?? false },
            set: { _ in recipe?.toggleScreenAwake?() }
        )
    }

    /// A held key does not repeat the command: a repeat that came while ⌘J opened the
    /// assistant closed it again.
    private func item(_ key: String, _ action: (() -> Void)?) -> some View {
        Button(Self.title(key)) {
            action?()
        }
        .disabled(action == nil)
        .buttonRepeatBehavior(.disabled)
    }

    private func tabItem(_ tab: AppTab, shortcut: Character) -> some View {
        let selectTab = app?.selectTab
        return item(tab.menuTitleKey, selectTab.map { select in { select(tab) } })
            .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
    }

    private static func title(_ key: String) -> String {
        Bundle.currentLocalizedString(key)
    }
}

private extension AppTab {
    /// The section titles of the tab bar (`AppTab.title`).
    var menuTitleKey: String {
        switch self {
        case .discover: "discover.nav.discover"
        case .recipes: "discover.nav.my-recipes"
        case .shopping: "discover.nav.shopping"
        case .profile: "discover.nav.profile"
        case .importTab: "discover.nav.import"
        case .assistant: "assistant.title"
        }
    }
}

extension View {
    /// ⌘F (spec 081, US6): this list's search field takes the focus asked for by
    /// `AppShellCoordinator.requestRecipeSearchFocus`. Applied after `.searchable`.
    /// `popToList` brings the phone stack back to the list first and says whether it
    /// popped. iPad on iOS 18+ only (`.searchFocused`); the iPhone search is untouched.
    func iPadRecipeSearchFocus(
        coordinator: AppShellCoordinator,
        popToList: (() -> Bool)? = nil
    ) -> some View {
        modifier(IPadRecipeSearchFocus(coordinator: coordinator, popToList: popToList))
    }
}

private struct IPadRecipeSearchFocus: ViewModifier {
    let coordinator: AppShellCoordinator
    let popToList: (() -> Bool)?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            content.modifier(IPadRecipeSearchFocusTaker(coordinator: coordinator, popToList: popToList))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct IPadRecipeSearchFocusTaker: ViewModifier {
    let coordinator: AppShellCoordinator
    let popToList: (() -> Bool)?

    @FocusState private var isSearchFocused: Bool

    func body(content: Content) -> some View {
        content
            .searchFocused($isSearchFocused)
            .onChange(of: coordinator.recipeSearchFocusRequestEpoch) { _, _ in
                takeRequestedFocus()
            }
            .onAppear {
                // The list that ⌘F brought on screen (another tab, «Свернуть»).
                takeRequestedFocus()
            }
    }

    private func takeRequestedFocus() {
        guard coordinator.consumeRecipeSearchFocusRequest() else { return }
        let popped = popToList?() ?? false
        Task { @MainActor in
            // The field must be in the window: after the tab switch or the pop.
            try? await Task.sleep(for: .milliseconds(popped ? 500 : 250))
            isSearchFocused = true
        }
    }
}
