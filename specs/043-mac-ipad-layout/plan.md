# План: Mac и iPad — адаптивная оболочка

**Ветка**: `043-mac-ipad-layout` | **Дата**: 2026-07-01 | **Spec**: [spec.md](./spec.md)

## Summary

Расширить нативный клиент с phone-only `TabView` на **двухрежимную оболочку**: compact (`TabView`) и regular (`NavigationSplitView` по HIG). Поведение — web parity; chrome — системный SwiftUI. Три инкремента: (A) iPad regular, (B) Mac target, (C) nested detail split + polish.

Технический центр — **`AdaptiveAppShell`** + `AppShellCoordinator`, без дублирования sync/auth.

## Technical Context

| Поле | Значение |
|------|----------|
| Language | Swift 5.9+, SwiftUI |
| Dependencies | Существующие: RecipeScalerCore, yrs, GRDB, socket.io-client-swift |
| Storage | UserDefaults (layout prefs); Y.Doc без изменений |
| Testing | XCTest UI + unit (`AppShellCoordinatorTests`), snapshot optional |
| Target Platform | iOS 17+ (iPhone + iPad), **macOS 14+** (новый target) |
| Performance | Переключение layout &lt; 300 ms; split drag 60 fps |
| Constraints | Constitution: CRDT-first, web parity, offline-first, native UI, i18n |
| Scale | ~15 новых/изменённых Swift view files, 1 macOS target, 0 backend |

## Constitution Check

| Gate | Статус | Комментарий |
|------|--------|-------------|
| CRDT-first | ✅ Pass | Только UI shell; данные через существующий `YjsSyncService` |
| Web parity | ✅ Pass | Поведение `main-nav.ts`, split widths, auto-select first recipe |
| Offline-first | ✅ Pass | Layout prefs local; sync lifecycle на shell level (007) |
| Native UI | ✅ Pass | `NavigationSplitView` + system sidebar; WKWebView только в description (019) |
| Phased delivery | ⚠️ Justified | Mac = новая платформа; iPad wide = Phase 6 из PRD, явный запрос пользователя |
| i18n | ✅ Pass | Reuse `discover.nav.*`; новые keys только для layout chrome |
| Docs | ✅ Pass | Эта спека + `layout.md` + contracts |

### Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected |
|-----------|------------|------------------------------|
| macOS target (4th platform) | Пользовательский запрос Mac app | Catalyst-only — хуже меню/окна/keyboard; web wrapper — нарушает Native UI |
| Два layout mode | Web имеет `isWide` / `!isWide` | Только iPad без Mac — не закрывает запрос |
| Nested NavigationSplitView in detail | Ingredients\|description @ 640 pt + persisted widths | Single scroll — хуже UX на wide iPad/Mac |

## Project Structure

### Documentation

```text
specs/043-mac-ipad-layout/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── layout.md
├── contracts/adaptive-shell-layout.md
└── checklists/requirements.md
```

### Source Code (новое / ключевое)

```text
RecipeScalerNative/
├── Views/
│   ├── AppShellView.swift              # delegates to AdaptiveAppShell
│   ├── AdaptiveAppShell/
│   │   ├── AdaptiveAppShell.swift      # compact TabView vs regular NavigationSplitView
│   │   ├── CompactAppShell.swift       # extracted current TabView body
│   │   ├── RegularAppShell.swift       # NavigationSplitView root
│   │   ├── AppSidebarView.swift        # List .sidebar style — NOT web icon strip
│   │   ├── RecipesSplitColumns.swift   # content + detail columns for Recipes tab
│   │   ├── TimerInspector.swift        # toolbar + inspector for regular mode
│   │   ├── ImportSidebarAction.swift   # intercept import without selection change
│   │   └── AdaptiveListRow.swift       # touch: swipeActions; macOS: pointer row
│   │       └── PointerRowActions.swift   # hover reveal + trackpad strip + contextMenu
│   └── RecipeDetail/
│       └── RecipeDetailNestedSplit.swift  # P2: nested NavigationSplitView
├── ViewModels/
│   └── LayoutPreferencesStore.swift    # persisted widths, lastRecipesRoute
├── Routing/
│   └── AppShellCoordinator.swift       # + wide selection state
RecipeScalerMac/                        # NEW TARGET
├── RecipeScalerMacApp.swift
└── (symlink/share sources via Xcode target membership)
RecipeScalerNativeTests/
└── AdaptiveLayoutTests.swift
```

**Structure Decision**: Один monorepo target `RecipeScalerNative` для iOS + новый `RecipeScalerMac` с shared `RecipeScalerCore` и conditional compilation `#if os(macOS)` только для menu/keyboard/window.

## Фазы реализации

### Фаза A — iPad wide (MVP, P1)

**Цель**: iPad landscape получает sidebar + recipe split без Mac target.

| # | Задача | Файлы |
|---|--------|-------|
| A1 | `LayoutMode` + `LayoutPreferencesStore` | new |
| A2 | Extract `CompactAppShell` из `AppShellView` | `AppShellView.swift` |
| A3 | `RegularAppShell` + `AppSidebarView` (`List` sidebar) | new |
| A4 | `RecipesSplitColumns` + coordinator selection | `AppShellCoordinator.swift` |
| A5 | Auto-select first recipe / folder | mirror web |
| A6 | `TimerInspector` toolbar/inspector | `TimerManager` |
| A7 | Assistant toolbar vs FAB | `AdaptiveAppShell.swift` |
| A8 | UI tests `forceLayout=wide` | tests |
| A9 | `layout.md` audit + `audit-ui-layout.sh` | specs |

**Verify**: `xcodebuild -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build test`

### Фаза B — macOS target (P1)

| # | Задача | Файлы |
|---|--------|-------|
| B1 | Xcode target `RecipeScalerMac`, macOS 14 SDK | `project.pbxproj` |
| B2 | Share RecipeScalerCore + native sources (exclude UIKit-only) | pbxproj, `#if os` |
| B3 | `RecipeScalerMacApp` → `AppContainer` + `ContentView` | new |
| B4 | Menu commands Import + tab shortcuts | `RecipeScalerMacApp.swift` |
| B5 | Window min size + titlebar | SwiftUI `WindowGroup` |
| B6 | Exclude Watch bridge, push, haptics, tab bar UIKit reader | conditional compile |
| B7 | `AdaptiveListRow` / `PointerRowActions` on Mac; iOS rows unchanged | views |
| B8 | Mac QA: trackpad strip, hover shopping delete, context menus | views |

**Verify**: `xcodebuild -scheme RecipeScalerMac -destination 'platform=macOS' build`

### Фаза C — Detail split + polish (P2)

| # | Задача |
|---|--------|
| C1 | `RecipeDetailSplitContainer` @ 640 pt threshold |
| C2 | Persist `recipe-ingredients-width` |
| C3 | Shopping wide header (single row) |
| C4 | Collapsible sidebar below wide threshold on Mac |
| C5 | Deep link → split selection |
| C6 | Accessibility audit sidebar + splitter |

## Дизайн оболочки

```mermaid
flowchart TB
    subgraph entry [ContentView]
        AUTH[Auth gate]
        ADAPT[AdaptiveAppShell]
    end
    subgraph modes [Layout mode]
        COMPACT[CompactAppShell<br/>TabView + Bottom chrome]
        WIDE[WideAppShell<br/>SidebarNav + Content]
    end
    subgraph wideContent [Wide content by tab]
        RS[RecipeSplitView<br/>list | detail]
        SINGLE[Single column<br/>Discover / Shopping / Profile]
    end
    AUTH --> ADAPT
    ADAPT -->|compact| COMPACT
    ADAPT -->|wide| WIDE
    WIDE --> RS
    WIDE --> SINGLE
```

### Regular vs compact (HIG-first)

```swift
// Primary: environment horizontalSizeClass + NavigationSplitView column visibility
@Environment(\.horizontalSizeClass) private var horizontalSizeClass

var usesRegularShell: Bool {
    horizontalSizeClass == .regular
    // iPhone: always .compact → TabView
}
```

Geometry thresholds (280 / 320 / 640 pt) — только для **min column widths** и nested detail split, не для переключения shell.

### Coordinator changes

`AppShellCoordinator` расширить:

```swift
var wideSelectedRecipeId: String?
var wideActiveFolderId: String?   // nil = flat root
var lastRecipesRoute: RecipesRoute = .root
```

При compact — selection через `NavigationPath` как сейчас. При wide — binding в `RecipeSplitView`. При смене режима — sync selection: если compact path содержит recipe id, восстановить в wide.

### Риски

| Риск | Mitigation |
|------|------------|
| `NavigationSplitView` 3-column on iPad | Custom HStack + web sidebar — не HIG, ломает collapse/Stage Manager |
| WKWebView description on Mac | Smoke test 019; отдельный `NSViewRepresentable` wrapper if needed |
| UIKit `TabBarTopOffsetReader` | `#if os(iOS)` only |
| GRDB / yrs on macOS | RecipeScalerCore already SPM — verify macOS platform in Package.swift |
| Snapshot tests iPhone-only | Separate iPad Pro snapshot config |

## Verify (все фазы)

```bash
# iOS compact regression
xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# iPad wide
xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' test

# Mac
xcodebuild -scheme RecipeScalerMac \
  -destination 'platform=macOS' build test

# Layout audit (после layout.md)
bash scripts/audit-ui-layout.sh specs/043-mac-ipad-layout
```

## Agent context

После утверждения плана обновить `<!-- SPECKIT START -->` в `Agents.md` → `specs/043-mac-ipad-layout/plan.md`.

## Открытые вопросы (закрыть до Фазы B)

1. **Mac App Store vs direct** — влияет только на signing; layout не блокирует.
2. **iPad portrait** — default compact (как iPhone); wide только при достаточной ширине (согласовано в spec).
3. **Скриншоты эталона** — prod timeout в CI agent; human QA на `recipe-scaler.ru` с userid `cfcd839f-56f2-4411-9632-7795b75f96d1` или local dev `localhost:5173`.