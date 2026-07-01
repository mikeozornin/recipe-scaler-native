# Research: Mac и iPad layout

**Дата**: 2026-07-01 | **Spec**: [spec.md](./spec.md)

## R1 — Эталон web layout

### Decision

Нативный wide-режим копирует **desktop web** (`isWide === true`), compact — **текущий iOS** (`isWide === false`).

### Rationale

- `docs/UI.md` сегодня ссылается на **mobile web** parity; пользователь явно запросил layout «как веб» для Mac/iPad — это wide-ветка `App.tsx`.
- `007-app-shell-navigation` вне scope оставил «Desktop sidebar»; 043 закрывает этот gap.

### Web sources (проверено в коде)

| Поведение | Файл |
|-----------|------|
| Wide threshold | `App.tsx` → `getMinDesktopWidth` |
| Sidebar 5 tabs + import + assistant slot | `sidebar-nav.tsx` |
| Bottom nav compact | `bottom-nav.tsx` |
| Tab reset logic | `utils/main-nav.ts` |
| Recipe list\|detail split | `App.tsx` L887–929 |
| Detail ingredients\|description split @ 640px | `recipe-detail.tsx` → `useIsContainerWide` |
| Timer mobile vs desktop | `App.tsx` L1116–1144, `timer-panel.tsx` |
| Persisted widths | `recipe-list-width`, `recipe-ingredients-width` localStorage |
| Shopping header wide | `shopping-list-page.tsx` `isWide` prop |

### Alternatives considered

| Alternative | Rejected because |
|-------------|------------------|
| Только `NavigationSplitView` без custom split | Не покрывает triple pane и persisted widths |
| iPad всегда wide | Portrait и Split View ломают UX; веб тоже схлопывается |
| Отдельное SwiftUI для Mac без shared shell | Двойная поддержка coordinator/nav |

---

## R2 — Платформа Mac: Catalyst vs native macOS

### Decision

**Native macOS target** (`RecipeScalerMac`) с shared Swift sources + `RecipeScalerCore`, не Mac Catalyst.

### Rationale

- Пользователь хочет «приложение для мака» — native menus, `⌘` shortcuts, resizable windows — проще с `#if os(macOS)` чем Catalyst quirks.
- `RecipeScalerCore` / yrs / GRDB — проверяемые на macOS через SPM; UIKit-зависимости (`TabBarTopOffsetReader`, haptics, push) изолируются `#if os(iOS)`.
- Catalyst тянет iOS tab bar metaphors; пришлось бы всё равно строить wide shell.

### Alternatives considered

| Alternative | Rejected because |
|-------------|------------------|
| Mac Catalyst | Tab bar / safe area / WKWebView edge cases; слабее menu bar |
| SwiftUI multiplatform `.macOS(.v14)` single target | Watch extensions, push, Live Activity смешиваются в один pbxproj сложнее |
| Web PWA only on Mac | Не native offline shell, нет App Intents parity |

---

## R3 — Определение compact vs regular (обновлено после HIG review)

### Decision

**Primary: `horizontalSizeClass` + `NavigationSplitView` column visibility.** Geometry thresholds только для min column widths и nested detail split.

### Rationale

- Apple HIG: iPad regular → sidebar + split; compact → stack / tab bar. SwiftUI реализует это через size class и `NavigationSplitView`, не pixel math.
- Web `isWide` по `window.innerWidth` — справочник для **min widths** (280/320/640), не для выбора shell.
- Stage Manager / Split View: системный collapse надёжнее кастомного threshold.

### Implementation note

```text
compact  → TabView (iPhone; iPad compact column)
regular  → NavigationSplitView (sidebar + columns)
inner split @ 640pt → nested NavigationSplitView in detail column
```

---

## R4 — iPad уже в target, Mac — нет

### Decision

Фаза A только меняет iOS target UI; Фаза B добавляет `RecipeScalerMac`.

### Evidence

`project.pbxproj`: `TARGETED_DEVICE_FAMILY = "1,2"` для основного app; `SUPPORTED_PLATFORMS` без `macosx`.

`docs/PRD.md` §10: «iPad adaptation — iPhone only initially» — снимаем ограничение в 043.

---

## R5 — Assistant и Import в regular (обновлено)

### Decision

- Import: sidebar row / toolbar; intercept без смены selection (`tabview.md` compose pattern).
- Assistant regular: **toolbar**; compact: FAB.
- **Отклонено**: web `assistant-sidebar-slot` — не HIG.

### Web reference (behavior only)

Reset tabs, sheet content — как web; placement — toolbar/inspector.

---

## R7 — HIG / SwiftUI alignment (2026-07-01)

### Decision

Корневая оболочка regular = **`NavigationSplitView`** + **`List` sidebar**, не кастомный web chrome.

### Rationale

| Было в draft | HIG / SwiftUI |
|--------------|---------------|
| Fixed 80px icon sidebar | `List` + `.listStyle(.sidebar)`, collapsible |
| HStack list\|detail рядом с sidebar | 3-column `NavigationSplitView` |
| Desktop timer fixed right | Toolbar / `.inspector` |
| Assistant footer slot | `ToolbarItem` |
| Pixel `isWide` threshold | `horizontalSizeClass` |

### Sources

- `docs/UI.md` §«Стандартные компоненты iOS»
- `swiftui-ui-patterns/references/split-views.md`
- `swiftui-ui-patterns/references/tabview.md` (import intercept)
- Apple HIG: iPad — sidebar navigation, split view, collapsible sidebar

---

## R8 — Hover vs touch / swipe input (2026-07-01)

### Decision

**`InteractionProfile`**: `.touch` = all iOS (iPhone + iPad); `.pointer` = macOS only. Orthogonal to `LayoutMode` (compact/regular).

### Rationale

- Web: `AdaptiveRow` — mobile → `SwipeableRow` (finger); desktop → `DesktopScrollableRow` (trackpad swipe + wheel).
- Web shopping: `group-hover:opacity-100` on `md+` only; assistant footer `max-md:opacity-100` (always on touch widths).
- User requirement: iPad wide layout **≠** desktop hover actions; same **actions**, different affordances.
- iPad with trackpad: web `useDevice` still classifies iPad as mobile → finger swipe; native mirrors this.

### Hover

| Screen | macOS | iPad/iPhone |
|--------|-------|-------------|
| Shopping delete | hover-reveal button | swipe or always-visible |
| Assistant footer | hover-reveal | always visible |
| Recipe row actions | trackpad strip / context menu | `.swipeActions` |

### Swipe

| Platform | Mechanism |
|----------|-----------|
| iOS | `.swipeActions`, finger |
| macOS | Trackpad horizontal gesture (`DesktopScrollableRow` parity), `contextMenu`; not `.swipeActions` |

### Alternatives rejected

| Alternative | Why |
|-------------|-----|
| `horizontalSizeClass` drives hover | iPad regular would get desktop hover — wrong |
| Same `.swipeActions` on Mac | Not HIG; poor trackpad UX |
| `deviceHasHover` on iPad + trackpad → pointer | Breaks user rule «hover не на iPad» |

---

## R6 — Скриншоты prod/dev

### Status

Автоматический захват `https://recipe-scaler.ru` из agent sandbox: **ERR_TIMED_OUT**. Local dev `localhost:5173` — не запущен.

### Fallback

- Визуальный эталон: `layout.md` + ссылки на web components.
- Ручная верификация: prod с `localStorage.userId = cfcd839f-56f2-4411-9632-7795b75f96d1` (пользовательский hint).
- Web repo assets: `recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md` §14 screenshots для collections (частичный overlap).

### Action for human

Перед Фазой A приложить в `specs/043-mac-ipad-layout/screenshots/`:

- `web-wide-recipes.png` (≥1180px width)
- `web-wide-shopping.png`
- `web-compact-recipes.png` (390px)