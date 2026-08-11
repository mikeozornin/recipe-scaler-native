# Спецификация: iPad-адаптация — sidebar + multi-column layout

**Ветка**: `063-ipad-adaptation`
**Дата**: 2026-08-11
**Статус**: DRAFT
**Зависимости**: `007` (app shell navigation), `011` (Discover public), `019` (description editor — плавающий таймер не должен ломать keyboard compensation)
**Эталон**: Apple HIG — Multiple columns on iPad (Mail, Notes); web `.card-grid` (`repeat(auto-fill, minmax(280px, 1fr))`); Apple `NavigationSplitView` best practices

## Контекст

Приложение сейчас iPhone-only: `TARGETED_DEVICE_FAMILY = 1` на main target, в коде **ноль** `horizontalSizeClass`/`userInterfaceIdiom` проверок, все экраны построены под compact width. На iPad работает через compatibility mode (растянутое iPhone-окно с гигантским таббаром).

При этом навигационный слой **готов к split-view**: каждый таб имеет собственный `NavigationStack(path:)` с типизированными route-ами (`RecipesRoute`, `DiscoverRoute`), единый `AppShellCoordinator` владеет тремя `NavigationPath`. Экраны Discover (`DiscoverCollectionView`, `DiscoverPublicProfileView`) уже используют adaptive multi-column grid `DiscoverRecipeCardGrid` (parity с вебом, 280pt min).

Веб-референс по сеткам — единый CSS grid класс `.card-grid { grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)) }`, применяемый на discover, public profile, discover collection. Recipe detail в вебе использует container query `@container (min-width: 640px)` для двухколоночного layout.

## Цель

Нативная iPad-адаптация: sidebar-навигация вместо растянутого таббара, multi-column grids для Discover и публичных списков, column layout (мастер + деталка) для рецептов, ограниченная ширина для Profile. iPhone UI остаётся без изменений через size-class switch.

## Пользовательские сценарии

### US1 — Sidebar на iPad (P1)

**Когда** пользователь открывает app на iPad в landscape, **тогда** слева виден sidebar (Discover / Import / Recipes / Shopping / Profile), справа — содержимое выбранного раздела. Переключение раздела не закрывает текущий стек.

### US2 — Рецепты: column layout (P1)

**Когда** пользователь в разделе Recipes, **тогда** слева (в master-колонке) виден список коллекций или плоский список рецептов (в зависимости от `viewMode`), а тап по рецепту открывает деталку справа. Master и detail видны одновременно **в обеих ориентациях** (portrait и landscape) — двухколоночный layout сохраняется.

### US3 — Discover multi-column (P1)

**Когда** пользователь открывает Discover на iPad, **тогда** коллекции и профили отображаются в adaptive grid (минимум 2 колонки при width ≥ 600pt), как в вебе.

### US4 — Публичный профиль / коллекция в 2+ колонки (P1)

**Когда** пользователь проваливается в публичный профиль или кураторскую коллекцию, **тогда** список рецептов отображается multi-column grid (как `DiscoverRecipeCardGrid` уже делает, но сейчас master-detail может сузить доступную ширину — нужно ≥2 колонки в detail column).

### US5 — Публичный рецепт в Discover (P1)

**Когда** пользователь открывает публичный рецепт из Discover, **тогда** контент (hero + тело) показывается в column не шире ~700pt по центру, не растягиваясь на весь экран.

### US6 — Профиль ограниченной ширины (P1)

**Когда** пользователь открывает Profile, **тогда** grouped List ограничен шириной ~700pt и центрирован, не растягивается на 1100pt+.

### US7 — Таймер поверх контента на iPad (P1)

**Когда** запущен таймер и пользователь находится в любой секции на iPad, **тогда** MobileTimerPanel показывается как floating overlay внизу detail column (как mini-player в Music), а не привязан к таббару.

### US8 — iPhone без регрессий (P0)

**Когда** пользователь открывает app на iPhone, **тогда** остаётся существующий TabView с 5 вкладками, без визуальных или поведенческих изменений.

## Требования

### FR-IPAD-001 — Targeted device family

`TARGETED_DEVICE_FAMILY = "1,2"` на main таргете `RecipeScalerNative` (Debug + Release конфиги). Extensions (`Share`/`Action`/`HomeWidget`/`TimerLiveActivity`) остаются `1`. `RecipeScalerNativeWatch` остаётся `4`. `Info.plist` уже содержит `UISupportedInterfaceOrientations~ipad` для всех 4 ориентаций — изменений не требуется.

### FR-IPAD-002 — Size-class switch в AppShell

`AppShellView.body` проверяет `@Environment(\.horizontalSizeClass)`:
- `.compact` → существующий `TabView` (без изменений, пути для iPhone)
- `.regular` → `NavigationSplitView` с sidebar

### FR-IPAD-003 — Sidebar (iPad)

`AppSidebarView` (новый) отображает 5 элементов (Discover / Import / Recipes / Shopping / Profile) с теми же SF Symbols, локализованными titles и `accessibilityIdentifier`, что в `AppTab`. Import тапает → презентует `ImportRecipeSheet` (как сейчас на табе). Селекция сохраняется через `AppShellCoordinator` (existing `selectedTab` семантика сохраняется как alias).

### FR-IPAD-004 — Recipes column layout (iPad)

В разделе Recipes на `.regular`: master-колонка показывает текущий корневой view (`CollectionsRootView` или flat list, зависит от `viewMode`), detail — `YDocRecipeDetailView` при выбранном рецепте. NavigationSplitView используется для двух-колоночного отображения (sidebar + master), без третьего уровня (sidebar / master / detail) — simplicity важнее.

### FR-IPAD-005 — Discover multi-column (iPad)

`DiscoverRootView` использует `DiscoverRecipeCardGrid` (или эквивалент) для отображения коллекций и профильных карточек. На width ≥ 600pt — минимум 2 колонки. Web parity через существующий `DiscoverRecipeCardLayout.minimumColumnWidth = 280`.

### FR-IPAD-006 — Discover public profile / collection multi-column

`DiscoverCollectionView` и `DiscoverPublicProfileView` **уже** используют `DiscoverRecipeCardGrid`. Требуется только проверить, что `availableWidth` корректно вычисляется внутри detail column (sidebar отнимает ~320pt, доступная ширина остаётся ≥ 600pt в landscape). Минимум 2 колонки в landscape.

### FR-IPAD-007 — Profile max-width (iPad)

`AccountView` оборачивается в `.frame(maxWidth: 700)` на `.regular`, центрируется через внешний `.frame(maxWidth: .infinity)`. Section headers и rows наследуют ограничение.

### FR-IPAD-008 — Recipe detail max-width (iPad)

`YDocRecipeDetailView` и `DiscoverRecipeView` контент (за исключением hero image, который может быть full-bleed) оборачивается в `maxWidth: 700-800pt` на `.regular`, центрируется.

### FR-IPAD-009 — Floating MobileTimerPanel (iPad)

В sidebar-режиме `MobileTimerPanel` презентуется как `.overlay(alignment: .bottom)` на detail column, не через `safeAreaInset(.bottom)`/`safeAreaBar`/`tabViewBottomAccessory`. Edit-mode suppression (`timerManager.setSuppressPanelSafeAreaInset`) становится no-op на `.regular` — плавающая панель не блокирует editor.

### FR-IPAD-010 — AssistantFAB на iPad

`AssistantFabButton` остаётся как `.overlay(alignment: .bottomTrailing)` на detail column. Отступ от низа больше не зависит от `tabBarTopOffsetFromLayoutBottom` (таббара нет) — фиксированный margin от floating timer panel или safe area.

### FR-IPAD-011 — Assistant sheet на iPad

Тап по FAB открывает `AssistantSheet` в том же режиме, что на iPhone (`.sheet` с `.appOpaqueSheetPresentationPlain()` — full-bleed). Поведение ассистента не меняется: history слева / new chat справа, keyboard Done, voice mode, attach picker. На iPad sheet открывается поверх detail column, не растягиваясь на sidebar — `.presentationDetents([.large])` или системный default для `.sheet` на iPad (`formSheet`-стиль).

### FR-IPAD-012 — Глубокие ссылки на iPad

Все существующие deep-link routes (`openRecipe`, `openShoppingList`, `openPublicProfile`, etc.) работают на iPad: выбирают соответствующий sidebar item и прокидывают path в detail column. Семантика `AppShellCoordinator.handleDeepLink` сохраняется.

## Вне scope

- iPhone UI — остаётся на TabView, без изменений
- Stage Manager / multi-window (`WindowGroup` дополнительные окна)
- Drag-and-drop между колонками (recipe drag from list to collection)
- Multiple selection в списках
- iPad-специфичные widgets (HomeWidget остаётся iPhone-only в этой spec)
- Локализация: используем существующие ключи (sidebar — те же `discover.nav.*` что и tab bar)
- Adaptive Sidebar toggle (`sidebarToggle`) — используем системное поведение `NavigationSplitView`
- Web recipe detail 2-column layout (`@container recipe-content`) — отдельная spec, если потребуется

## Критерии успеха

- **SC-001**: App устанавливается и запускается на iPad Air 11" (M3) симуляторе без compatibility mode
- **SC-002**: На iPad в landscape виден sidebar + detail; на iPhone остаётся TabView (скриншот-доказательство)
- **SC-003**: Discover на iPad в landscape показывает ≥2 колонки карточек
- **SC-004**: Public profile / collection на iPad в landscape показывают ≥2 колонки рецептов
- **SC-005**: Profile (`AccountView`) на iPad — width ≤ 700pt, центрирован
- **SC-006**: Recipe detail (private и public) на iPad — content width ≤ ~800pt, центрирован
- **SC-007**: Floating MobileTimerPanel работает на iPad; edit mode в recipe detail не блокируется panel
- **SC-008**: Все существующие UI-тесты на iPhone проходят без регрессий
- **SC-009**: Deep links работают на iPad (Spotlight → рецепт в My Recipes; Universal Link → Discover)
- **SC-010**: Поворот iPad portrait ↔ landscape сохраняет состояние (sidebar видим, selection не сбрасывается); в обеих ориентациях Recipes section — двухколоночный (master + detail видны одновременно)

## Границы

- **В scope**: 5 фаз (spec scaffold / sidebar shell / detail layouts / floating timer / verification); ~7 production файлов + 3 тестовых
- **Вне scope**: см. секцию выше
- **STOP conditions**:
  - iPhone UI regression — возврат и фикс
  - Floating timer ломает `DescriptionEditorScrollKeyboardPolicy` в recipe editor
  - Существующие UI-тесты на iPhone падают

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | PASS | Слой sync не трогается; route enums без изменений |
| Web parity | PASS | card-grid `minmax(280px, 1fr)` → `DiscoverRecipeCardLayout.minimumColumnWidth = 280` (уже существует) |
| Offline-first | PASS | Без изменений в storage/sync |
| Native UI | PASS | NavigationSplitView — идиоматичный iPad pattern (Mail, Notes, Settings) |
| Phased delivery | PASS | 5 фаз, каждая независимо верифицируется |
| i18n | PASS | Существующие localized keys используются (sidebar переиспользует tab labels) |
| Documentation | PASS | `docs/UI.md` получит секцию "iPad patterns" |

## Downstream consumers

- **SwiftUI views**: `AppShellView`, `RecipeListView`, `DiscoverRootView`, `ShoppingListView`, `AccountView`, `YDocRecipeDetailView`, `DiscoverRecipeView`, `CollectionsRootView`, `DiscoverCollectionView`, `DiscoverPublicProfileView`, `MobileTimerPanel` (+ новый `AppSidebarView`)
- **Cross-process**: N/A — widgets и extensions остаются iPhone-only в этой spec; watch без изменений
- **Sync boundaries**: N/A — Yjs/CRDT не трогается
- **Persisted state**: `@AppStorage(RecipeFolderRoutes.viewModeStorageKey)` — без изменений; sidebar selection persistent не нужен (defaults to `.recipes`)
- **Tests / verify scripts**:
  - `RecipeScalerNativeTests/AppShellCoordinatorTests.swift` — alias `selectedTab` или rename в `selectedSidebarItem`
  - `RecipeScalerNativeTests/AppContainerTests.swift` — 2 сайта
  - `RecipeScalerNativeTests/RecipeScalerNativeTests.swift:1182` (`testAppTabBarSymbolsExistInUIKit`) — должен остаться зелёным
  - Новый `scripts/verify-ipad-layout.sh`

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| Запуск на iPad Air 11" landscape | Sidebar виден, detail column отображает корневой view выбранной секции | `verify-ipad-layout.sh:assert-sidebar-visible` |
| Запуск на iPhone (любой) | `tab_discover`/`tab_recipes`/`tab_shopping`/`tab_profile` присутствуют в UI hierarchy | `RecipeScalerNativeUITests/testTabBarVisibleOnCompact` |
| Discover на iPad landscape, N коллекций, N≥4 | Grid показывает ≥2 колонки | `verify-ipad-layout.sh:assert-discover-min-2-columns` |
| Profile на iPad landscape | Ширина List ≤ 700pt | `verify-ipad-layout.sh:assert-profile-max-width` |
| Запущен таймер + пользователь в YDocRecipeDetailView на iPad | Floating timer overlay виден; editor keyboard compensation работает | `verify-ipad-layout.sh:assert-floating-timer-no-editor-regression` |
| Поворот iPad portrait → landscape (или наоборот) | Sidebar остаётся видимым; selection не сбрасывается; scroll positions сохраняются | `RecipeScalerNativeUITests/testSidebarSurvivesRotation` |
| Recipes section на iPad в portrait | Master (список) и detail (выбранный рецепт) видны одновременно | `verify-ipad-layout.sh:assert-recipes-two-column-portrait` |
| Тап по AssistantFAB на iPad | Assistant sheet открывается; FAB скрывается, как на iPhone | `verify-ipad-layout.sh:assert-assistant-sheet-opens` |
| Spotlight tap → `/recipe/{id}` на iPad | Sidebar → Recipes; detail показывает YDocRecipeDetailView | `verify-ipad-layout.sh:assert-deeplink-sidebar-selection` |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| Sidebar selection change | `selectedTab` (sync, @Observable) | N/A — нет suspension points | N/A | N/A |
| Deep link navigation в detail column | `selectedTab` + `NavigationPath` (sync writes) | N/A | N/A | N/A |
| Floating timer overlay show/hide | `timerManager.activeTimers` observation | N/A — declarative | N/A | N/A |

N/A для async side effects — sidebar refactor чисто декларативный (SwiftUI reactivity). Существующие async lifecycle в `YjsSyncService`, `AssistantVoiceRecorder`, `DescriptionEditorWebView` не трогаются.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| Logout (iPad) | `coordinator.resetShellStateForLogout()` сбрасывает sidebar selection в `.recipes`, чистит 3 NavigationPath | Существующие sync tasks без изменений | UserDefaults без изменений; keychain без изменений | Spotlight index без изменений | После logout sidebar на `.recipes`, detail пустой или with placeholder |
| Account switch (iPad) | То же, что logout + bootstrap нового user | Существующие flow | То же | То же | Sidebar на `.recipes`, новый user виден в Profile |
| Cold start (iPad) | `AppShellCoordinator.init` → default `.recipes`; sidebar selection persisted не нужен (всегда старт с `.recipes`) | Существующие bootstrap | Существующее persisted state (no new keys) | Existing | После cold start sidebar на `.recipes`, существующий path drained из deep link |
| Size class change (rotation / Stage Manager resize) | `horizontalSizeClass` switch в `AppShellView.body` | N/A — declarative | N/A | N/A | Selection сохраняется через `coordinator.selectedTab`; существующий navigation path сохраняется |

## Cross-target contracts

- **Canonical owner**: `AppShellCoordinator` (один source of truth для selection + 3 NavigationPath)
- **Writer/reader targets**: только main app target. Extensions / widgets / watch не затрагиваются
- **Validator/normalizer**: существующий `DeepLinkRouter` парсер без изменений
- **Raw literal exceptions**: N/A — никаких новых hardcoded literals

## Locale / theme consumers

- **SwiftUI environment**: на sidebar переиспользуются существующие `discover.nav.*` localized keys через `AppTab.title`
- **UIKit / notification categories**: без изменений
- **Widgets / Live Activities / App Intents**: без изменений (extensions остаются iPhone-only)
- **Cached or generated assets**: без изменений
- **`.system` effective value**: sidebar appearance наследуется от system chrome (NavigationSplitView)

## Compatibility / migration

- **Current format/contract**: existing route enums (`RecipesRoute`, `DiscoverRoute`) — без изменений
- **Previous supported format**: N/A (новый feature)
- **Missing version/default behavior**: `horizontalSizeClass == .compact` → fallback на TabView (iPhone behavior); `regular` → split-view
- **Unknown future version/ID behavior**: N/A
- **Required legacy fixture tests**: существующие `AppShellCoordinatorTests` должны остаться зелёными (rename поля coordinator → либо alias, либо update тестов)

## Unknown IDs and fallback policy

- DEBUG/CI: unknown `AppTab` case → hard failure (existing `CaseIterable` semantics сохраняются)
- Release: sidebar показывает дефолтный `.recipes` при любом unknown state (default в `AppShellCoordinator`)
- Legacy aliases: N/A — новых ID не появляется

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app` assertion |
|---------|----------|---------------|----------------|------------------------|
| N/A — никаких новых assets | N/A | N/A | N/A | N/A |

Sidebar использует existing SF Symbols (`globe`, `square.and.arrow.down`, `book`, `cart`, `person`) из `AppTab.tabBarSymbol`. Никаких новых raster/vector assets.

## Human gates

- [ ] Спека (этот файл) reviewed пользователем
- [ ] После Phase 2 (sidebar shell): скриншоты iPad portrait + landscape reviewed
- [ ] После Phase 3 (detail layouts): скриншоты Discover multi-column reviewed
- [ ] После Phase 4 (floating timer): UX review — расположение floating timer vs FAB
- [ ] Финальный review: UITest regression на iPhone + acceptance на iPad

## Verification

- `bash scripts/verify-plan-state.sh specs/063-ipad` — валидация spec/plan/tasks целостности
- `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' build` — green
- `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone Air' build` — green
- `xcodebuild ... test` на iPhone (существующие тесты) — без регрессий
- `bash scripts/verify-ipad-layout.sh` (новый) — iPad snapshot + behavioral assertions (sidebar visible, discover ≥2 колонки, profile max-width, floating timer overlay)
- `bash scripts/lint-i18n.sh` — без изменений, но запустить для верности
- Expected: build green на обеих платформах, 0 regressions на iPhone, все SC-001..SC-010 → PASS

## Артефакты

```
specs/063-ipad/
├── spec.md          # этот файл
├── tasks.md         # будет создан после approval spec-и
├── research.md      # codebase map из exploration (5 фаз зависят от findings)
└── screenshots/
    ├── before-ipad-baseline-portrait.png
    ├── before-ipad-baseline-landscape.png
    └── after-phase-*.png  # после каждой фазы
```
