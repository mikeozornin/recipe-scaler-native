# Contract: adaptive shell (web behavior ↔ HIG chrome)

**Spec**: [spec.md](../spec.md) | **Date**: 2026-07-01 (HIG revision)

## Principle

| Layer | Source |
|-------|--------|
| **Behavior** (tabs, reset, auto-select, widths) | Web `main-nav.ts`, `App.tsx` |
| **Chrome** (sidebar, columns, timers, assistant) | Apple HIG + SwiftUI `NavigationSplitView` |

## Mode matrix

| Condition | Native shell | Navigation |
|-----------|--------------|------------|
| `horizontalSizeClass == .compact` | `TabView` + bottom tabs | Per-tab `NavigationStack` |
| `horizontalSizeClass == .regular` | `NavigationSplitView` | Sidebar `List` + columns |

## Column layout (regular)

| Tab | Columns |
|-----|---------|
| Recipes | sidebar \| list (content) \| detail |
| Discover, Shopping, Profile | sidebar \| content |

## Web behavior → native mapping

| Web | Native (regular) |
|-----|------------------|
| `SidebarNav` 5 items | `AppSidebarView` `List` rows |
| `BottomNav` | `TabView` (compact only) |
| `navigateToMainNav` reset | Coordinator reset on re-tap sidebar row |
| `AutoSelectFirstRecipe` | `selectedRecipeId` on folder enter |
| `recipe-list-width` | `layout.recipe-list-width` + column preferences |
| `recipe-ingredients-width` | nested split in detail column |
| `TimerPanel desktop` | `TimerInspector` toolbar/inspector |
| `TimerPanel mobile` | `MobileTimerPanel` (compact) |
| `AssistantSheet` + sidebar slot | `AssistantSheet` + toolbar button |
| `ImportNavTrigger` | Import intercept (no selection change) |

## Interaction profile (orthogonal to layout)

| Profile | OS | Row actions | Hover-only UI |
|---------|-----|-------------|---------------|
| `touch` | iOS (iPhone, iPad) | `.swipeActions` finger | Forbidden |
| `pointer` | macOS | trackpad strip + `contextMenu` | Allowed (web `group-hover` screens) |

Web reference: `AdaptiveRow`, `DesktopScrollableRow`, `SwipeableRow`.

### Per-screen mapping

| Screen | Web mobile | Web desktop | Native touch | Native pointer |
|--------|------------|-------------|--------------|----------------|
| Recipe list row | SwipeableRow | DesktopScrollableRow | swipeActions | trackpad + contextMenu |
| Shopping item delete | swipe / visible | group-hover delete | swipeActions | hover button + contextMenu |
| Assistant message footer | always visible | group-hover | always visible | hover reveal |

## Explicit chrome differences (allowed)

| Web | Native |
|-----|--------|
| 80px icon-only sidebar | System sidebar list with labels |
| Fixed right timer column | Toolbar / inspector |
| CSS padding-left sidebar | NavigationSplitView columns |
| `isWide` window width | `horizontalSizeClass` |

## Min widths (shared semantics)

| Zone | Min pt |
|------|--------|
| List column | 280 |
| Detail column | 320 |
| Inner detail split | 640 |

## macOS additions

- `SidebarCommands()`
- Menu File → Import
- `⌘1…⌘5`, `⌘I`, `⌘K`