# Layout: Mac / iPad adaptive shell (HIG-aligned)

**Spec**: [spec.md](./spec.md) | **Status**: Static audit PASS — human review required
**Platform reference**: Apple HIG iPad navigation, SwiftUI `NavigationSplitView`  
**Behavior reference**: web `App.tsx`, `main-nav.ts`

## Compact mode (unchanged)

Эталон: `AppShellView` + `docs/UI.md`. iPhone; iPad `horizontalSizeClass == .compact`.

```
┌─────────────────────────────┐
│  [MobileTimerPanel]         │
├─────────────────────────────┤
│   NavigationStack content   │
│                    [FAB]    │
├─────────────────────────────┤
│ TabView — 5 bottom tabs     │
└─────────────────────────────┘
```

## Regular mode — NavigationSplitView (Recipes, 3 columns)

```
┌──────────────┬──────────────┬─────────────────────────┐
│  SIDEBAR     │  CONTENT     │  DETAIL                 │
│  (List)      │  Recipe list │  Recipe detail          │
│              │  min 280 pt  │  min 320 pt             │
│  Discover    │              │                         │
│  Import *    │  [selection] │  [selectedRecipeId]     │
│  Recipes  ●  │              │                         │
│  Shopping    │              │                         │
│  Profile     │              │                         │
│              │              │  [toolbar: timers, asst] │
└──────────────┴──────────────┴─────────────────────────┘
     ↑ collapsible          ↑ system resize
```

`*` Import — action row, не selected state.

### Sidebar (HIG)

| Property | Value |
|----------|-------|
| Component | `List` + `.listStyle(.sidebar)` |
| Row | `Label(title, systemImage:)` — Martian via `.appBody()` / `.appFootnote()` |
| Width | System adaptive (не fixed 80 pt) |
| Collapse | `NavigationSplitViewColumnVisibility.automatic` + sidebar toggle |
| Touch | min 44 pt row height |
| Selection | `List(selection:)` или explicit highlight on `AppTab` |

**Не делать**: узкая icon-only колонка как `sidebar-nav.tsx`.

### Content + Detail (Recipes)

- List column: existing `RecipeListView` / collections drill-in
- Detail: `YDocRecipeDetailView` or `ContentUnavailableView`
- Selection binding — no `NavigationLink` push to detail in regular mode
- Persist list width → `layout.recipe-list-width`

При переходе compact → regular pushed recipe detail удаляется из iPad `NavigationPath`: folder route остаётся в content column, а рецепт становится selection третьей detail-колонки. При обратном переходе regular → compact bridge восстанавливает folder + recipe path.

## Regular mode — 2 columns (Discover / Shopping / Profile)

```
┌──────────────┬──────────────────────────────────────────┐
│  SIDEBAR     │  CONTENT (NavigationStack)               │
│              │  full width of content column            │
└──────────────┴──────────────────────────────────────────┘
```

Detail column hidden. Shopping share → `.toolbar`, not second header row.

## Detail inner split (P2, inside detail column)

When Mac detail column width ≥ 640 pt — native `HSplitView`:

```
┌─────────────────────────┬──────────────────┐
│ Ingredients + metadata  │ Description      │
│ (content)               │ (detail)         │
└─────────────────────────┴──────────────────┘
```

Below 640 pt: single `ScrollView` (current mobile layout). iPad regular keeps the existing shared iOS detail surface until its separate runtime-polish pass.

Native Mac window: default `1280×800`, minimum `960×640`; system sidebar/list/detail columns remain usable below the default size.

## Timers (regular)

**Not** fixed right column (web desktop).

| Placement | When |
|-----------|------|
| `ToolbarItemGroup` on detail | 1–2 active timers, compact chips |
| `.inspector(isPresented:)` | Expanded timer list |

Respect 019 suppress when description editor focused.

## Assistant (regular)

`ToolbarItem(placement: .primaryAction)` or `.automatic` trailing — opens `AssistantSheet`. No FAB. No sidebar footer slot.

## Typography & color

Per `docs/UI.md`. Sidebar uses system list chrome; Martian in labels. Brand accent — toolbar buttons / FAB only, not full-row sidebar fill.

## Interaction (hover vs touch)

| | iPad / iPhone (`touch`) | Mac (`pointer`) |
|--|-------------------------|-----------------|
| List row delete/pin/cart | Finger `.swipeActions` | `.swipeActions` + context menu |
| Shopping item delete | Swipe / visible | Hover-reveal button (web `group-hover`) |
| Assistant copy/time | Always visible | Hover-reveal |
| Hover-only buttons | **Forbidden** | Allowed per spec |

iPad regular layout does **not** switch to pointer/hover patterns.

## Accessibility

| Element | Requirement |
|---------|-------------|
| Sidebar | `List` accessibility rotor; identifiers `tab.discover` etc. |
| Column resize | System adjustable; no custom splitter a11y unless nested split |
| Selected section | `.isSelected` trait |

## Review checklist (human)

- [ ] iPad sidebar looks like a system app (Mail/Settings), not a web icon strip;
      labels, selection highlight and minimum row hit targets are usable
- [ ] iPad landscape Recipes shows sidebar | list | detail; selecting another
      recipe changes the detail column without a pushed navigation screen
- [ ] iPad regular remains touch-profile: row actions are available by finger
      swipe, and no action button appears only after hover
- [ ] Narrow iPad / Stage Manager window collapses through the system split
      behavior; the compact fallback shows bottom tabs and does not squeeze a
      three-column layout
- [ ] Compact↔regular transition preserves the selected recipe and active
      folder; returning to compact restores the folder + recipe path
- [ ] iPhone remains the existing compact shell: five bottom tabs, timer panel
      and assistant FAB
- [ ] Regular timers are in the toolbar/inspector, not a fixed right overlay;
      description editing still applies the existing suppress rule
- [ ] Assistant is a regular toolbar action and has no regular-mode FAB;
      Import opens its sheet without changing sidebar selection
- [ ] Sidebar hide/show works with the system toggle and content expands after
      the sidebar is hidden
- [ ] Native Mac default and minimum windows keep sidebar, list and detail
      usable; wide detail shows ingredients | description and a narrow detail
      falls back to one vertical scroll
- [ ] Mac row actions are available through swipe gestures and context menu;
      destructive delete is confirmable
- [ ] The same action results are observable on iPad and Mac for selection,
      pin, add-to-shopping and delete; destructive delete is confirmable
- [ ] VoiceOver/accessibility navigation exposes sidebar identifiers,
      selected traits, row action labels and system-adjustable column dividers
