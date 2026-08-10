# Data model: adaptive layout state

**Spec**: [spec.md](./spec.md) | **Date**: 2026-07-01

Локальное UI-состояние. **Не** синхронизируется через Y.Doc.

## LayoutMode

| Значение | Условие |
|----------|---------|
| `compact` | `horizontalSizeClass == .compact` или `NavigationSplitView` stack / `forceLayout == compact` (DEBUG) |
| `regular` | `horizontalSizeClass == .regular` и multi-column split visible |

Derived at runtime; не персистится (кроме DEBUG override). **Не** использовать pixel `isWide` для shell selection.

## InteractionProfile

| Value | Condition |
|-------|-----------|
| `touch` | `os(iOS)` — iPhone и iPad, любой LayoutMode |
| `pointer` | `os(macOS)` |

Controls row affordances (swipe vs trackpad, hover-only buttons). **Не** зависит от `horizontalSizeClass` или regular layout.

## SidebarSelection

Порт `MainNavTab` из `main-nav.ts`:

| Case | Root content |
|------|----------------|
| `discover` | `DiscoverRootView` |
| `recipes` | `RecipeSplitView` (wide) / `RecipeListView` stack (compact) |
| `shopping` | `ShoppingListRootView` |
| `profile` | `AccountRootView` |

`import` — не selection value; открывает `ImportPresentation` sheet.

## RecipeSplitState (wide, recipes tab)

| Field | Type | Notes |
|-------|------|-------|
| `selectedRecipeId` | `String?` | nil → empty detail pane |
| `activeFolderId` | `String?` | nil = flat `/`; UUID or `all`/`uncategorized` |
| `listScrollOffset` | `CGFloat` | Preserve like web `recipeListScrollPosition` |
| `listWidth` | `CGFloat` | Default 320; min 280 |

Transitions:

- User taps recipe in list → set `selectedRecipeId`
- User navigates folder → set `activeFolderId`, auto-select first recipe if any
- Delete selected recipe → select next in list or nil
- Tab away from recipes → preserve state in coordinator

## RecipeDetailSplitState (wide, inside detail pane)

| Field | Type | Notes |
|-------|------|-------|
| `middlePaneWidth` | `CGFloat` | Default 400 |
| `isContainerWide` | `Bool` | Derived: detail pane width ≥ 640 |

## PersistedLayoutPreferences

Storage: `UserDefaults.standard` (keys namespaced `layout.*`).

| Key | Type | Default | Web analog |
|-----|------|---------|------------|
| `layout.recipe-list-width` | `Double` | 320 | `recipe-list-width` |
| `layout.recipe-ingredients-width` | `Double` | 400 | `recipe-ingredients-width` |
| `layout.last-recipes-route` | `String` | `/` | in-memory `lastRecipesRoute` on web |

## AppShellCoordinator extensions

Existing: `selectedTab`, per-tab `NavigationPath`, import sheet, deep links.

Add:

```swift
struct WideRecipesState: Equatable {
    var selectedRecipeId: String?
    var activeFolderId: String?
    var listScrollOffset: CGFloat = 0
}
```

Coordinator methods:

- `selectRecipeInWideSplit(_ id: String?)`
- `openFolderInWideSplit(_ folderId: String?)`
- `resetDiscoverIfNested()` — port `navigateToMainNav` discover branch
- `resetRecipesIfInDetail()` — port recipes reset

## Validation rules

- `listWidth >= 280`
- `middlePaneWidth >= 240` (TBD in layout.md audit)
- Persist on drag end (debounce 0 ms, save immediately)

## Non-goals

- Sync layout prefs across devices (web тоже local per browser)
- Store layout in Y.Doc / server