# Layout: Mac / iPad adaptive shell (HIG-aligned)

**Spec**: [spec.md](./spec.md) | **Status**: Draft — human review required  
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

## Regular mode — 2 columns (Discover / Shopping / Profile)

```
┌──────────────┬──────────────────────────────────────────┐
│  SIDEBAR     │  CONTENT (NavigationStack)               │
│              │  full width of content column            │
└──────────────┴──────────────────────────────────────────┘
```

Detail column hidden. Shopping share → `.toolbar`, not second header row.

## Detail inner split (P2, inside detail column)

When detail column width ≥ 640 pt — nested `NavigationSplitView`:

```
┌─────────────────────────┬──────────────────┐
│ Ingredients + metadata  │ Description      │
│ (content)               │ (detail)         │
└─────────────────────────┴──────────────────┘
```

Below 640 pt: single `ScrollView` (current mobile layout).

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
| List row delete/pin/cart | Finger `.swipeActions` | Trackpad horizontal swipe → strip; context menu |
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

- [ ] Sidebar looks like system iPad app (Mail/Settings), not web icon strip
- [ ] Recipes: 3 columns on iPad landscape; selection drives detail
- [ ] iPhone unchanged
- [ ] Timers in toolbar/inspector, not right overlay
- [ ] Sidebar hide/show works with system toggle