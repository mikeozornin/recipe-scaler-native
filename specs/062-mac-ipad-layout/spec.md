# Спецификация: Mac и iPad — адаптивная оболочка (desktop web parity)

**Ветка**: `043-mac-ipad-layout`
**Дата актуализации**: 2026-08-10
**Статус**: In progress — native macOS shell, основные Mac surfaces, keyboard/accessibility action contract и compact↔regular selection bridge реализованы, iOS/Mac compile gates зелёные; Mac startup/navigation smoke, backend-independent iPad/iPhone shell smoke, iPad regular Assistant toolbar smoke, live iPad regular selection→detail E2E, recipe touch-swipe E2E и Shopping touch-delete E2E пройдены, а human acceptance, Stage Manager, Mac pointer-action acceptance и iPad regular detail polish остаются
**Зависимости**: `007-app-shell-navigation` (мобильная оболочка), `026-recipe-collections` (split list/detail на вебе), существующие экраны вкладок
**Эталон поведения (wide)**: `recipe-scaler-web/.../App.tsx`, `utils/main-nav.ts` — состав разделов, reset, auto-select, persisted widths
**Эталон chrome (wide)**: **Apple HIG iPad** + **SwiftUI `NavigationSplitView`** — не pixel-copy `sidebar-nav.tsx`
**Терминология**: «iPad reference» здесь означает системные wide-layout паттерны iPad. Это не режим Xcode **Mac (Designed for iPad)**: приложение собирается отдельным native macOS target `RecipeScalerMac`, а iPad и Mac расходятся по interaction profile.
**Эталон (compact / mobile)**: текущий `AppShellView.swift` (TabView + `MobileTimerPanel`)

**План поставки**: сначала platform feasibility и Recipes vertical slice на native macOS, затем iPad regular и остальные regular-поверхности. До начала Mac UI обязателен gate: `RecipeScalerCore` и Yrs должны иметь доказанный macOS build path.

**Примечание по документам**: numeric prefix `043` занят `specs/043-ingredient-illustrations` на актуальном `master`; документы этой feature перенесены в canonical path `specs/062-mac-ipad-layout`, историческое имя ветки сохранено.

## Контекст

Нативное приложение сегодня ориентировано на **iPhone**: пять вкладок внизу, один `NavigationStack` на вкладку, панель таймеров над tab bar. Веб-клиент на широких экранах переключается на **другую оболочку** (sidebar + master-detail). На iPad/Mac **повторяем те же пользовательские потоки**, но **оболочку строим на системных паттернах Apple**, а не копируем веб-chrome:

- **Sidebar** — `NavigationSplitView` + `List` в стиле `.sidebar` (сворачиваемый системным toggle);
- **Recipes** — трёхколоночный split: sidebar | список | деталь (авто-выбор первого рецепта);
- **Другие вкладки** — двухколоночный split: sidebar | контент;
- **Таймеры (wide)** — toolbar / inspector, не кастомная «правая колонка как на вебе»;
- **Ассистент (wide)** — toolbar (trailing / bottom bar), compact — FAB;
- **Import** — sidebar row или toolbar action (как «compose» tab — не меняет selection).

`docs/PRD.md` Phase 6 откладывал iPad; пользовательский запрос — **Mac + iPad** с layout «как веб», а на узких экранах — **адаптация как сейчас на iOS**.

Проект уже собирается с `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad). Adaptive iOS shell содержит compact/regular ветки; native macOS target `RecipeScalerMac` добавлен отдельной схемой. Composition root находится в `AppContainer`: Mac переиспользует тот же `AppContainer`, `AppShellCoordinator`, `YjsSyncService`, `AuthService` и `TimerManager`, а iOS-only OS surfaces не входят в Mac membership.

## Цель

Дать пользователям на **iPad** и **Mac** тот же информационный каркас и навигационные привычки, что на desktop web, **в рамках HIG и SwiftUI**, сохранив проверенный **мобильный** UX на iPhone и в compact-режиме.

## Платформенная модель (HIG + SwiftUI)

Приоритет: **системное поведение Apple** → паритет логики веба → визуальная близость к вебу. См. также `docs/UI.md` §«Стандартные компоненты iOS».

### Compact (iPhone; iPad compact width)

| Аспект | Паттерн |
|--------|---------|
| Навигация | `TabView` + `NavigationStack` per tab (как сейчас, 007) |
| Таймеры | `MobileTimerPanel` над tab bar |
| Ассистент | FAB |
| Триггер | iPhone всегда compact; iPad `horizontalSizeClass == .compact` или системный stack от `NavigationSplitView` |

### Regular / Wide (iPad regular; Mac)

| Аспект | Паттерн | HIG / SwiftUI |
|--------|---------|---------------|
| Корневая оболочка | `NavigationSplitView` | Стандартный iPad/macOS master-detail; sidebar collapsible |
| Sidebar | `List` + `.listStyle(.sidebar)`; строки icon + label | Не узкая icon-only колонка как `sidebar-nav.tsx` |
| Видимость колонок | `NavigationSplitViewColumnVisibility` (`.automatic`) | Pinch / sidebar toggle; Stage Manager — системный collapse |
| Recipes | 3 columns: sidebar \| list \| detail | Как Mail / Notes; list selection drives detail |
| Discover / Shopping / Profile | 2 columns: sidebar \| content | Detail column скрыт |
| Import | Row в sidebar **или** toolbar; intercept без смены selection | Аналог compose-tab в `swiftui-ui-patterns/tabview.md` |
| Таймеры | `.toolbar` / `.inspector` на уровне detail | Не fixed overlay справа (отличие от web desktop) |
| Ассистент | `.toolbar` на root / detail | Не custom slot внизу sidebar |
| Keyboard (Mac) | `⌘1…⌘5`, `⌘I`, `⌘K` + `SidebarCommands()` | macOS HIG |

**Взаимодействие со строками и hover** — см. §«Модель взаимодействия (hover vs touch)»; iPad **не** получает hover-only actions.

На macOS `horizontalSizeClass` не считается достаточным источником истины: native target явно выбирает regular presentation, а узкое окно управляется `NavigationSplitView`/column visibility и не превращается в iOS bottom-tab chrome.

### Вложенные split (recipe detail, P2)

Внутри **detail column** — второй уровень:

1. На Mac реализован `HSplitView` (ingredients/metadata | description) при ширине detail ≥ 640 pt; iPad regular пока использует существующий `YDocRecipeDetailView` до отдельного runtime-polish этапа.
2. **Fallback**: вертикальный scroll (как compact) при узкой detail column.

Persisted widths — через `LayoutPreferencesStore`/`UserDefaults`: list divider и Mac inner ingredients pane используют общие clamped keys, с min widths как на вебе.

### Что сознательно **не** копируем с веба

| Web | Native (HIG) |
|-----|--------------|
| Fixed 80 px icon sidebar | System sidebar list, adaptive width |
| `TimerPanel` fixed right edge | Toolbar / inspector |
| Assistant portal в sidebar footer | Toolbar button |
| Bottom tabs на iPad regular | Sidebar (tabs только в compact) |
| CSS `isWide` по `window.innerWidth` | `horizontalSizeClass` + column visibility; geometry только для inner split |

**Поведенческий паритет с вебом сохраняем**: состав разделов, reset tabs, auto-select first recipe, persisted list/middle widths, folder routes, **набор действий на строках** (pin, delete, cart, collections, shopping delete).

## Модель взаимодействия (hover vs touch)

Эталон веба: `AdaptiveRow` → `SwipeableRow` (mobile) / `DesktopScrollableRow` (desktop); shopping — `group-hover:opacity-100` только на `md+`; assistant footer — `group-hover` + `max-md:opacity-100`.

Нативно разделяем не «wide vs compact», а **`InteractionProfile`**:

| Profile | Платформы | Ввод | Hover-only UI | Свайп строк |
|---------|-----------|------|---------------|-------------|
| **`touch`** | iPhone, **iPad** (все режимы) | палец; опционально trackpad как pointer для scroll | **Запрещён** | **Свайп по экрану** — `.swipeActions` |
| **`pointer`** | macOS | мышь / trackpad | **Разрешён** где на вебе `group-hover` | **Trackpad** — горизонтальный жест / scroll, не finger swipe |

**Сопоставимость действий**: на всех платформах доступны **те же операции** (delete, pin, add to shopping, collections, share…), но **разные affordance**:

| Действие | touch (iOS) | pointer (macOS) |
|----------|-------------|-----------------|
| Delete recipe / ingredient | trailing `.swipeActions` | context menu + hover-кнопка в strip **или** trackpad swipe → delete strip |
| Pin / cart / collections | leading `.swipeActions` | trackpad swipe right → strip; context menu |
| Shopping: delete item | swipe (если есть) или явная кнопка | hover-reveal delete (как web `group-hover`) + context menu |
| Assistant: copy / timestamp | всегда видимы (как `max-md:opacity-100`) | hover-reveal footer (как web desktop) |
| Row highlight | tap selection | hover background + click |

### Правила hover (FR-043-014)

- Элементы с `opacity-0` до hover **только** при `InteractionProfile == .pointer`.
- На **iPad regular** layout шире, но profile остаётся **`touch`** — никаких скрытых до hover кнопок в списках.
- Допустим на iPad: системный **selection highlight** sidebar/list при trackpad (не action reveal).
- Recipe/Shopping/Collection rows на iOS: существующие `.swipeActions` из 026/024 **без изменений** в touch profile.

### Правила свайпа (FR-043-015)

- **touch**: только SwiftUI `.swipeActions` / finger drag; full-swipe policy как сейчас (`allowsFullSwipe: false` на recipe rows).
- **pointer**: finger `.swipeActions` **не использовать**; вместо них:
  1. **Trackpad horizontal swipe / scroll** — раскрытие left/right strip (паритет `DesktopScrollableRow` + AppKit `NSEvent.scrollWheel` / `scrollingDeltaX`);
  2. **Context menu** (`contextMenu`) — полный набор действий;
  3. Hover-кнопки где веб показывает `group-hover` (shopping delete).
- Один непрерывный жест не переходит strip→strip без neutral (паритет web `SwipeableRow`).

### Реализация (plan)

- `InteractionProfile` = `.pointer` iff `os(macOS)`; иначе `.touch` (iPhone и iPad).
- Общий action contract: ветка touch → текущие row + `swipeActions`; Mac pointer adapter → `MacRecipeRow` с hover, AppKit `scrollWheel`, context menu и keyboard focus.
- Не дублировать бизнес-логику — shared action handlers.

## Пользовательские сценарии

### US1 — Автоматический выбор оболочки (P1)

**Когда** пользователь открывает приложение, **тогда** система выбирает режим:

| Режим | Условие (логическое) | Поведение |
|-------|----------------------|-----------|
| **Compact** | iPhone; iPad `horizontalSizeClass == .compact`; `NavigationSplitView` в stack | `TabView` + bottom tabs + `MobileTimerPanel` + FAB |
| **Regular / Wide** | iPad regular width; macOS window | `NavigationSplitView` с sidebar (см. US2–US5) |

**Триггер regular** — в первую очередь **`horizontalSizeClass`** и **column visibility** SwiftUI, не ручной pixel threshold. Geometry-порог (sidebar + 280 + 320 pt) применяется только к **вложенному** split внутри detail (US4) и к min window size на Mac.

При повороте / resize iPad система **сама** переводит `NavigationSplitView` между multi-column и stack; приложение сохраняет `selectedRecipeId` и tab selection.

При таком переходе coordinator переносит recipe из compact pushed route в regular detail selection, сохраняя folder route в list column; при возврате в compact восстанавливается прежний folder + recipe path.

**Независимый тест**: iPad Pro 13" landscape — sidebar + list + detail; iPhone 16 — bottom tabs без sidebar.

### US2 — Sidebar навигация (P1)

**Когда** активен regular/wide-режим, **тогда** первая колонка `NavigationSplitView` — **системный sidebar** (`List`, `.listStyle(.sidebar)`):

1. Discover  
2. Import (действие → sheet, **не** меняет `selection`)  
3. My recipes  
4. Shopping  
5. Profile  

**HIG-требования**:

- Sidebar **сворачивается** стандартным toggle / жестом (не always-visible fixed strip);
- Строки — **icon + text label** (Martian, `discover.nav.*`), min touch 44 pt;
- Активный раздел — system selection highlight (не обязательно brand tint на всю строку);
- **Ассистент не в footer sidebar** — только toolbar (US7).

**Поведение reset** — паритет `main-nav.ts`:

- повторный тап Discover с вложенного маршрута → корень Discover;
- повторный тап Recipes при открытой детали → корень списка (`lastRecipesRoute`).

**Независимый тест**: Discover nested → тап Discover в sidebar → root; sidebar скрывается/показывается системным control.

### US3 — Рецепты: трёхколоночный split (P1)

**Когда** regular-режим и выбран Recipes, **тогда** `NavigationSplitView` показывает **три колонки**:

| Колонка | Содержимое |
|---------|------------|
| Sidebar | US2 |
| Content (list) | `RecipeListView` / folder list; min ~280 pt |
| Detail | `YDocRecipeDetailView` или empty state |

- Selection в list column **программно** связывает detail (`selectedRecipeId`);
- Ширина list column **resizable** (system divider + persisted `recipe-list-width`);
- Folder drill-in меняет content column; detail обновляется;
- Папка с рецептами → **авто-выбор первого** (web parity);
- Нет selection / пустая папка → `ContentUnavailableView` в detail («Выберите рецепт»);
- **Без push-навигации** list→detail в regular (selection-based, как Mail).

**Независимый тест**: iPad landscape Recipes — три колонки видны; тап другого рецепта меняет detail без анимации push.

### US4 — Деталь рецепта: вложенный split (P2)

**Когда** ширина **Mac detail column** ≥ ~640 pt, **тогда** внутри detail — `HSplitView`: ingredients/metadata | description. На iPad regular в текущем срезе сохраняется shared `YDocRecipeDetailView` с вертикальным scroll.

- Persisted `recipe-ingredients-width`; min widths по вебу;
- При detail column &lt; 640 pt — **один** вертикальный scroll (как compact), без горизонтального сжатия.

**Независимый тест**: широкий Mac detail — две подколонки; сузить окно до stack — scroll, данные на месте. iPad regular inner split — отдельный acceptance item.

### US5 — Discover, Shopping, Profile в regular (P1)

**Когда** regular-режим и активна вкладка ≠ Recipes, **тогда** **две колонки**: sidebar | content. Detail column **скрыта** (`NavigationSplitView` two-column mode).

- Внутри content — свой `NavigationStack` для nested routes (Discover drill-in);
- **Shopping** — toolbar actions (share) в `.toolbar`, не второй header row;
- **Profile** — `Form` / Settings pattern; на Mac — readable max-width по HIG;
- **Discover** — без изменения card layout; navigation внутри content column.

### US6 — Таймеры (P1)

| Режим | Паттерн |
|-------|---------|
| **Compact** | `MobileTimerPanel` (без изменений) |
| **Regular** | Активные таймеры в **toolbar** detail/root и/или **inspector** (`inspector(isPresented:)`); сворачиваемая панель |

Не использовать web-style fixed right column overlay на iPad — конфликтует с system chrome и Stage Manager.

Inspector/toolbar MUST уважать suppress rules из 019 (description formatting bar).

### US7 — Import и Assistant (P1)

- **Import** — sidebar row или toolbar; открывает `ImportRecipeSheet`; **selection не меняется** (intercept pattern).
- **Assistant (regular)** — `ToolbarItem` (trailing); sheet; **без FAB**.
- **Assistant (compact)** — FAB (текущее).
- Sheet presentation — `.sheet(item:)` (swiftui-ui-patterns).

### US8 — Платформенные жесты и chrome (P2)

**iPad (regular, touch profile)**:

- Свайпы строк — **палец по экрану**, `.swipeActions` (как iPhone);
- **Нет** hover-only кнопок в списках (shopping delete, assistant footer и т.д.);
- Trackpad/mouse на iPad: scroll и system selection OK; **не** заменяют finger swipe actions;
- Split View / Stage Manager: compact shell при узкой колонке (US1).

**macOS (pointer profile)**:

- `WindowGroup` + min size; `SidebarCommands()`; `⌘1…⌘5`, `⌘I`, `⌘K`;
- Строки списков: **trackpad horizontal swipe** → strips + **context menu**; hover-reveal где web `group-hover`;
- Finger swipe на Mac **не** является primary affordance.

**iOS 18+ (опционально)**: adaptive `TabView` sidebar — отдельно от interaction profile.

### US11 — Сопоставимые действия, разный ввод (P1)

**Когда** пользователь выполняет действие над строкой (recipe, ingredient, shopping item), **тогда** результат одинаков на touch и pointer, но способ вызова зависит от profile:

| Сценарий | touch (iPad/iPhone) | pointer (Mac) |
|----------|---------------------|---------------|
| Удалить рецепт из списка | swipe trailing | trackpad swipe left **или** context menu **или** hover strip |
| Pin / cart / collections | swipe leading | trackpad swipe right **или** context menu |
| Удалить пункт shopping | swipe / visible control | hover delete button **или** context menu |
| Assistant copy | control всегда виден | виден on hover (+ keyboard) |

**Независимый тест**: iPad — delete shopping item без hover UI; Mac — delete появляется on row hover; оба удаляют item.

### US9 — Синхронизация и офлайн (P1)

Wide/compact переключение **не пересоздаёт** `YjsSyncService` и не сбрасывает offline queue. Смена ориентации iPad сохраняет выбранный рецепт и scroll position списка где возможно.

### US10 — Deep links и Spotlight (P2)

Universal Links / `recipe-scaler://` / Spotlight: на wide открывают вкладку Recipes, выделяют рецепт в split, на compact — текущее поведение push в stack.

## Функциональные требования

### FR-043-000 — Platform feasibility и target boundary

До добавления пользовательского UI native macOS target обязан иметь подтверждённый build path для `RecipeScalerCore`, Yrs/`YrsC` и всех зависимостей первого Recipes-среза. iOS-only slices, UIKit-only сервисы, watchOS/WidgetKit/ActivityKit и Share/Action extensions не должны попадать в Mac target membership.

Если Yrs нельзя собрать для macOS без смены ABI или source fallback, Mac implementation останавливается на feasibility report; iPad regular продолжает развиваться независимо.

Текущий evidence (2026-08-10): `Package.swift` объявляет `.macOS(.v14)`, ZIPFoundation присутствует и в SwiftPM, и в Xcode project, `swift build --target RecipeScalerCore --triple arm64-apple-macosx` проходит, а `Frameworks/YrsXCFramework.xcframework` содержит `macos-arm64_x86_64` вместе с iOS device/simulator slices. `xcodebuild` для `RecipeScalerNative` и `RecipeScalerMac` проходит; локальный Mac startup/AX smoke подтверждает 2/3-column shell и parsed descriptions, iPad Air landscape/portrait и iPhone compact shell smoke проходят через accessibility identifiers, отдельный live local-backend selection E2E подтверждает iPad row tap → detail column, `RegularRecipesShellSpec/test_regularRecipeKeepsTouchSwipeActions` подтверждает iPad recipe `swipeLeft` → trailing delete action, а `RegularShoppingShellSpec/test_regularShoppingKeepsTouchDeleteAction` — Shopping `swipeLeft` → `shopping_item_delete_<id>` (`Test-ipad-shopping-touch-delete.xcresult`, 1/1). Formal human acceptance, Stage Manager, Mac pointer actions и iPad regular detail polish остаются отдельными gate.

### FR-043-001 — Состав навигации

Пять разделов + Import sheet. i18n keys: `discover.nav.*` (как 007). Иконки — те же SF Symbols, что в `AppTab`.

### FR-043-002 — Триггер regular vs compact

- **Primary**: `#if os(macOS) → regular`; на iOS — `horizontalSizeClass` + `NavigationSplitView` column visibility (`.automatic`).
- **Secondary** (min sizes): list column ≥ 280 pt, detail ≥ 320 pt, inner detail split ≥ 640 pt — для clamp/persist, не для ручного переключения shell.
- iPhone: всегда compact `TabView`.

### FR-043-003 — Persist split widths

| Ключ (логический) | Default | Аналог веб |
|-------------------|---------|------------|
| `recipe-list-width` | 320 | localStorage |
| `recipe-ingredients-width` | 400 | localStorage |

Хранение: `UserDefaults` / App Group где уже используется для IPC.

### FR-043-004 — Compact fallback

На iPhone **ничего не меняется** без регрессий. iPad compact / stack mode → `TabView` bottom tabs. **Не показывать bottom tabs при regular + visible sidebar** (HIG: одна primary navigation).

### FR-043-011 — NavigationSplitView shell

Wide shell MUST использовать `NavigationSplitView` (не кастомный `HStack` + fixed sidebar). Column visibility: `.automatic`. Recipes: 3 columns; other tabs: 2 columns.

На iOS эти варианты являются двумя явными ветками shell: Recipes получает sidebar | list | detail, остальные regular surfaces — sidebar | content. Пустая `Color.clear` middle-column не используется, чтобы переключение Discover/Shopping/Profile не теряло системный sidebar.

### FR-043-012 — Sidebar presentation

Sidebar MUST быть `List` с `.listStyle(.sidebar)` (или эквивалент system sidebar). Запрещено: узкая web-like icon-only колонка 80 pt без text labels в regular mode.

### FR-043-013 — Timers и assistant placement

Regular: timers → toolbar/inspector; assistant → toolbar. Запрещено в v1: fixed trailing overlay column для таймеров (web desktop pattern).

### FR-043-014 — Hover-only actions

Запрещено на `InteractionProfile.touch` (iPhone + iPad). Разрешено на `.pointer` (macOS) для экранов с web `group-hover` (shopping list delete, assistant message footer). Assistant на touch — controls always visible (web `max-md` rule).

### FR-043-015 — Row swipe mechanics

| Profile | Mechanism |
|---------|-----------|
| `.touch` | `.swipeActions`, finger on screen |
| `.pointer` | Trackpad horizontal gesture (DesktopScrollableRow parity); `contextMenu`; no reliance on `.swipeActions` |

Neutral-between-strips rule preserved on both profiles where swipe strips apply.

### FR-043-016 — InteractionProfile derivation

```text
.pointer  ↔  os(macOS)
.touch    ↔  os(iOS)   // iPhone and iPad, including regular NavigationSplitView
```

Layout mode (compact/regular) **не** меняет InteractionProfile.

### FR-043-005 — Рецепты: selection model

В wide на вкладке Recipes обязателен **selectedRecipeId** (и опционально `activeFolderId`) на уровне shell coordinator. Смена вкладки sidebar сохраняет selection при возврате на Recipes.

### FR-043-006 — Коллекции и folder routes

Паритет `NATIVE_APP_COLLECTIONS.md` §7 в обоих режимах. В wide folder drill-in меняет левую колонку; правая — detail выбранного рецепта.

### FR-043-007 — Таймеры

`TimerManager.suppressPanelSafeAreaInset` и editing-description suppress — работают в обоих режимах. Desktop panel не конфликтует с description formatting bar (019).

### FR-043-008 — i18n

Новые строки только в `Localizable.xcstrings`. Подписи sidebar — те же keys, что tab bar.

### FR-043-009 — Accessibility

Sidebar items: `accessibilityIdentifier` по аналогии с `AccessibilityIdentifiers.tab*`. VoiceOver объявляет selected tab. Splitter — accessibility adjustable value.

### FR-043-010 — DEBUG / UI-test

Launch args из 007 (`-OpenTab=...`, `-MobileTimerPanelExpanded=1`, …) работают в обоих режимах. Новый DEBUG arg `-ForceLayout=compact|wide` используется для детерминированных UI-тестов.

## Key Entities

- **LayoutMode** — `compact` | `regular`; выводится из size class + platform.
- **InteractionProfile** — `touch` | `pointer`; `pointer` только macOS.
- **SidebarSelection** — активная main-nav вкладка (`MainNavTab` parity).
- **RecipeSplitState** — `listWidth`, `selectedRecipeId`, `activeFolderId`, `listScrollOffset`.
- **RecipeDetailSplitState** — `middlePaneWidth`, `isContainerWide`.
- **PersistedLayoutPreferences** — сохранённые ширины и последний `lastRecipesRoute`.

## Вне scope (v1)

- Отдельный watchOS / widget / Live Activity на Mac
- Share Extension / Action Extension на macOS
- Multi-window (два рецепта в двух окнах)
- Menu bar extra / CLI
- Pixel-perfect 1:1 с веб CSS (достаточно иерархии и поведения)
- v1/v2→v3 миграция рецептов (остаётся web-only)
- Переписывание Tiptap/description editor под native macOS WebView отличия (только QA)

## Допущения

- **Mac delivery**: native macOS target с общим `AppContainer`, `AppShellCoordinator` и `RecipeScalerCore`; первый вертикальный срез Recipes реализован, platform/runtime acceptance продолжается (детали в `plan.md`).
- **HIG &gt; web chrome**: визуальная оболочка следует Apple; **логика** (tabs, reset, splits, auto-select) — веб.
- **iOS 17+**: базовая реализация через `NavigationSplitView`; adaptive `TabView` sidebar — опциональная миграция на iOS 18+.
- Пользователь авторизован (seed / device token) — flow из 041 без изменений.

## Критерии успеха

- **SC-043-000**: До UI-реализации существует воспроизводимая проверка, которая собирает `RecipeScalerCore` и Yrs для macOS либо документирует блокирующий ABI/source-fallback результат. Репозиторный XCFramework содержит macOS slice, а `RecipeScalerMac` generic build зелёный; cold launch/sync runtime остаются acceptance gate.
- **SC-043-001**: На iPad Pro 12.9" landscape пользователь видит список и деталь рецепта без дополнительного tap в ≥ 95% сессий (empty collection — исключение с empty state).
- **SC-043-002**: На iPhone 15 UI-test suite 007/026 без регрессий (compact unchanged).
- **SC-043-003**: Переключение compact↔wide на iPad занимает &lt; 300 ms без потери selected recipe.
- **SC-043-004**: Ширина list split сохраняется после перезапуска приложения.
- **SC-043-005**: Поведение reset sidebar tabs совпадает с веб `navigateToMainNav` для Discover и Recipes (manual QA checklist).
- **SC-043-006**: Mac: min window показывает sidebar + list + detail без overflow.
- **SC-043-007**: iPad regular — sidebar скрывается/показывается системным control; после hide контент расширяется (не ломается layout).
- **SC-043-008**: На iPad shopping list нет кнопок, видимых только при hover; delete доступен без hover.
- **SC-043-009**: На Mac recipe row delete доступен без touch swipe (context menu или trackpad strip).

## Edge cases

- Поворот iPad compact↔regular — `NavigationSplitView` animates column collapse; sheet остаётся modal; selection сохраняется.
- Удаление selected recipe — selection → соседний или empty detail pane.
- Узкое Mac window — system stack mode; sidebar toggle, не bottom tabs.
- Discover nested + tab switch — независимые paths per sidebar selection (как per-tab paths в 007).
- Stage Manager narrow column — compact shell (TabView), не squeezed 3-column.
- VoiceOver: sidebar = `List`; selected tab trait; column changes announced.
- iPad + Magic Keyboard trackpad: interaction profile остаётся `touch`; swipe — через `.swipeActions`, не desktop wheel strips.
- Mac Book trackpad: profile `pointer`; horizontal two-finger swipe на row → strip, не iOS swipeActions.
- Mac target без Yrs macOS slice: приложение не объявляет готовый Recipes UI; сборка останавливается на explicit feasibility result.
