# Tasks: iPad-адаптация

**Input**: `specs/081-ipad-adaptation/` — [spec.md](./spec.md), [plan.md](./plan.md), [layout.md](./layout.md)  
**Prerequisites**: план одобрен человеком (plan.md §Human gates). Ответы на Q1–Q6 получены 2026-10-12 и внесены (spec.md §Clarifications).

## Format: `[ID] [P?] [Story] Описание — прототип`

- `[P]` — можно делать параллельно: другие файлы, нет зависимости от незавершённых задач той же фазы.
- `[USn]` — история из spec.md.
- В конце каждой задачи — состояние прототипа (`шаг/состояние`, layout.md §Карта состояний), с которым сверяется результат.
- Пути — от корня репозитория. Каждая задача рассчитана на одну сессию.
- **Общее правило всех фаз**: после каждой задачи iPhone-сборка и `bash scripts/test-fast.sh` зелёные. Это главный инвариант (plan.md §Positive invariants). Регресс на iPhone — STOP 1.

---

## Phase 1: Setup

**Purpose**: собирать, запускать и снимать приложение на iPad-симуляторе; включить семейство устройств iPad.

- [x] T001 [P] Создать `scripts/resolve-ipad-simulator.sh` по образцу `scripts/resolve-simulator.sh`:
  - выбирать доступный iPad-симулятор на самом новом runtime (предпочтение — «iPad Pro 11-inch (M4)», затем «iPad Air 11-inch»);
  - уважать переопределение `IPAD_SIM_ID`;
  - печатать UDID.

  Описать запуск в шапке скрипта. — `#recipes/sidebar`
- [x] T002 [P] Создать `scripts/verify-ipad-layout.sh`:
  - собирает приложение и ставит его на симулятор;
  - запускает только с уже существующими DEBUG-аргументами (`-OpenTab`, `-OpenRecipeId`, `-ShowAssistant`, `-StartInEditMode` и др. из `RecipeScalerNative/Utils/DebugLaunchOptions.swift`), чтобы эталон снимался на `master` без изменений Swift-кода. Скрипт расширят позже: T011 — состояния с `-IPadSidebarHidden` / `-IPadListHidden`, T049 — матрица окон через `-DebugWindowWidth`;
  - снимает скриншоты в `tmp/ipad-verify/<step>-<state>-<orient>-<window>.png`;
  - фиксирует статус-бар через `xcrun simctl status_bar override`.

  Режим `--iphone-regression`:
  - снимает те же экраны на iPhone-симуляторе (`scripts/resolve-simulator.sh`) и сравнивает их попиксельно с эталоном `tmp/ipad-verify/iphone-baseline/`;
  - `--capture-baseline` записывает эталон.

  Эталон снять **на текущем `master` до любых изменений Swift-кода**. — все 24 состояния, `#recipes/sidebar` … `#menubar/view` (layout.md §Карта состояний)
- [ ] T003 В `RecipeScalerNative.xcodeproj/project.pbxproj` поставить `TARGETED_DEVICE_FAMILY = "1,2"` для таргета `RecipeScalerNative` во всех конфигурациях (строки ~4158, ~4397, ~4419, ~4442).
  - Собрать для iPad и iPhone.
  - Проверить `plutil -extract UIDeviceFamily json -o - <app>/Info.plist` → `[1,2]`.
  - Ориентации `UISupportedInterfaceOrientations~ipad` в `RecipeScalerNative/Info.plist` уже есть — только проверить.

  — `#recipes/sidebar`
- [ ] T004 Проверить семейство устройств расширений (Share, Action, HomeWidget, TimerLiveActivity, ShareExtensionUI).
  - Собрать архив и выполнить validate в Xcode Organizer / `xcodebuild -exportArchive` с `-validate`.
  - Если валидация требует совпадения с приложением — поставить `"1,2"` у расширений без изменения их UI.
  - Результат записать в plan.md §Generated resources.
  - **Human gate**: нужна учётная запись App Store Connect.

  — `#import/text` (Share/Action Extension открывают импорт; инфраструктура)

**Checkpoint**: приложение ставится на iPad-симулятор и запускается без режима совместимости (сейчас — телефонная раскладка, растянутая на iPad; это ожидаемо). iPhone-эталон скриншотов снят. `verify-ui-smoke.sh` на iPhone зелёный.

---

## Phase 2: Foundational

**Purpose**: спайк на живом iPad-симуляторе и чистые основы. **Блокирует все истории.**

### Спайк (сначала, до любой вёрстки)

- [ ] T005 Спайк оболочки в отдельной временной ветке (код спайка не вливается). Проверить на iPad-симуляторе iPadOS 26.x пункты из plan.md §Результаты спайка:
  - **S1** — `TabView(.sidebarAdaptable)` + `TabSection` с динамическими коллекциями + `.sectionActions` + `.tabViewSidebarBottomBar`: без белого экрана, всё кликается;
  - **S2** — чтение и управление видимостью сайдбара;
  - **S3** — compact даёт нижний таб-бар, как `modernTabView`;
  - **S7** — оценка нескольких окон: можно ли держать `AppShellCoordinator` на сцену при общем `AppContainer` (`RecipeScalerNative/RecipeScalerNativeApp.swift:121`, `RecipeScalerNative/App/AppContainer.swift:65`) и что делать с `DeepLinkRouter.shared`.

  Заполнить вердикты в plan.md. При белом экране или некликабельности — STOP 2. — `#recipes/sidebar`, `#recipes/tabs`, окно ½
- [ ] T006 Спайк контента (та же временная ветка):
  - **S4** — вариант A (`NavigationSplitView` из двух колонок внутри `Tab`) против B (`HStack` из двух `NavigationStack`): тулбары обеих колонок, `.searchable` в колонке списка, список поверх рецепта;
  - **S5** — `.inspector` на уровне `TabView`, ширина 340, переход sheet ↔ inspector при смене size class с открытым чатом;
  - **S6** — `.popover` от пункта `Menu` и от `tabViewBottomAccessory`; есть ли аксессуар в режиме сайдбара.

  Записать выбор варианта A/B в plan.md (Р5) и в `docs/DECISIONS.md`. Если ломаются оба — STOP 3. — `#recipes/focus`, `#assistant/chat`, `#recipes/collections`, `#recipes/timers`

### Основы

- [ ] T007 [P] Создать `RecipeScalerNative/Views/IPad/IPadLayoutPolicy.swift`:
  - `IPadLayoutMetrics` — все константы из layout.md §Токены;
  - чистая `IPadLayoutPolicy.resolve(contentWidth:listCollapsedByUser:isEditing:) -> IPadLayout` (`listShown`, `detailWidth`, `twoColumns`, `toolbarStyle`, `showsListButton`, `shopVkusvillIconOnly`);
  - чистая `IPadLayoutPolicy.detailLeftWidth(preferred: CGFloat?, detailWidth:) -> CGFloat?` — формула `leftWidth` из layout.md §Токены; `nil` при одной колонке.

  Создать `RecipeScalerNativeTests/IPadLayoutPolicyTests.swift`:
  - каждый порог (560+321, 720, 600, 640) на значении и на 1 pt ниже;
  - `testPrototypeMatrix` — все строки layout.md §Матрица приёмки;
  - `testLeftColumnClamp`: без сохранённой ширины — 400; 200 → 320; 600 → 480; панель 720 → не шире 399, панель 760 → не шире 439 (правой ≥ 320); панель 719 → `nil`.

  — `#recipes/sidebar`, `#recipes/tabs`, `#assistant/chat`
- [ ] T008 [P] Создать `RecipeScalerNative/Views/IPad/AppLayoutMode.swift`:
  - `enum AppLayoutMode { case phone, padRegular }`;
  - `EnvironmentValues.appLayoutMode`, по умолчанию `.phone`;
  - чистая `AppLayoutMode.resolve(idiom:horizontalSizeClass:)`.

  Подключить в `RecipeScalerNative/ContentView.swift` (`rootChrome`, ~:192-210). Создать `RecipeScalerNativeTests/AppLayoutModeTests.swift` (`testPhoneIdiomIsAlwaysPhone`, `testPadCompactIsPhone`, `testPadRegularIsPadRegular`). — `#recipes/tabs` в окне ½ против всего экрана
- [ ] T009 Перевести `AppShellCoordinator.recipesPath` с `NavigationPath` на `[RecipesRoute]` (`RecipeScalerNative/Routing/AppShellCoordinator.swift:68`).
  - Обновить привязки в `RecipeScalerNative/Views/RecipeListView.swift` (:18, :40 и места использования), `RecipeScalerNative/Views/CollectionsRootView.swift`, `RecipeScalerNative/Views/CollectionFolderView.swift`, `RecipeScalerNative/Views/AppShellView.swift` (~:724, ~:805).
  - Убедиться, что путь нигде не сериализуется (`NavigationPath.CodableRepresentation`).
  - Создать `RecipeScalerNative/Routing/RecipesSelection.swift` (путь ↔ выбор, plan.md Р4) и `RecipeScalerNativeTests/RecipesSelectionTests.swift`: `testPathRoundTrip`, `testSelectingCollectionOpensFirstRecipe`, `testSelectionSurvivesModeSwitch`, `testDeletedSelectionFallsBack`.
  - Прогнать `RecipeScalerNativeTests/AppShellCoordinatorTests` и `verify-ipad-layout.sh --iphone-regression`.

  — `#recipes/collection`
- [ ] T010 [P] Создать `RecipeScalerNative/Views/IPad/AdaptivePresentation.swift`:
  - `.adaptivePopover(isPresented:arrowEdge:content:)` — при `.phone` ровно существующий `.sheet` с `appOpaqueSheetPresentation()` (`RecipeScalerNative/Utils/AppSheetChrome.swift`);
  - `.iPadReadableWidth(_:)` через `.contentMargins` / `frame(maxWidth:)` — при `.phone` без эффекта;
  - `.iPadFormSheet()` — `.presentationSizing(.form)` на iOS 18+.

  `#Preview` для обоих режимов. — `#recipes/collections`, `#shopping/recipe`, `#import/text`
- [ ] T011 [P] Идентификаторы и DEBUG-аргументы.
  - Добавить идентификаторы сайдбара, футера, коллекций сайдбара, колонки списка, кнопки «Список рецептов», инспектора, ✦ в `RecipeScalerNative/AccessibilityIdentifiers.swift` и `RecipeScalerNativeUITests/Helpers/Selectors.swift`.
  - Добавить DEBUG-аргументы `-IPadSidebarHidden`, `-IPadListHidden`, `-DebugWindowWidth <pt>` в `RecipeScalerNative/Utils/DebugLaunchOptions.swift` (только `#if DEBUG`; `-DebugWindowWidth` сужает корневой контейнер и подменяет `horizontalSizeClass` — для матрицы политики, не для системных переходов).
  - Расширить `scripts/verify-ipad-layout.sh` (T002): состояния со скрытым сайдбаром и скрытым списком через `-IPadSidebarHidden` / `-IPadListHidden`. Матрицу окон добавит T049.

  — `#recipes/tabs`, `#recipes/focus`

**Checkpoint**: вердикты S1–S7 записаны, вариант колонок выбран. `IPadLayoutPolicyTests`, `AppLayoutModeTests`, `RecipesSelectionTests`, `AppShellCoordinatorTests` зелёные. `verify-ipad-layout.sh --iphone-regression` — 0 отличий. iPad-ветки ещё не видны пользователю.

---

## Phase 3: User Story 1 — Нативная оболочка iPad (P1) — MVP

**Goal**: сайдбар, верхний и нижний таб-бары, телефонные экраны по центру, импорт в form sheet, без встряхивания.  
**Independent Test**: spec.md US1.

- [ ] T012 [US1] Создать `RecipeScalerNative/Views/IPad/IPadShellItem.swift`:
  - `enum IPadShellItem { case tab(AppTab), collection(String) }`;
  - вычисляемая привязка поверх `coordinator.selectedTab` и `coordinator.recipesPath` (plan.md Р2), перехват `.tab(.assistant)`;
  - запись `.collection(id)` зависит от параметра `isSplitActive`: `false` (US1, compact, телефонный стек) → путь `[.folder(id)]`, телефонный экран коллекции; `true` (активен `IPadRecipesSplitView`, включает T024) → `[.folder(id), .recipe(первый рецепт, folderContext: id)]`, пустая коллекция → `[.folder(id)]`.

  Создать `RecipeScalerNativeTests/IPadShellItemTests.swift` (`testAssistantDoesNotChangeSelection`, `testCollectionMapsToRecipesPath` — оба случая `isSplitActive`, `testDeepLinkPathMapsToCollection`). — `#recipes/sidebar`, `#recipes/collection`
- [ ] T013 [US1] Вынести корни вкладок из `modernTabBar` (`RecipeScalerNative/Views/AppShellView.swift` ~:709-770) в `RecipeScalerNative/Views/AppShellTabRoots.swift`. Только перенос: iPhone-дерево не меняется. Проверка — `verify-ipad-layout.sh --iphone-regression` и `AppShellNavigationSpec` на iPhone. — `#recipes/tabs` на iPhone (рефакторинг, вид не меняется)
- [ ] T014 [US1] Создать `RecipeScalerNative/Views/IPad/IPadAdaptiveTabView.swift`:
  - `TabView(selection:)` + `.tabViewStyle(.sidebarAdaptable)`;
  - вкладки «Подборки», «Рецепты» (счётчик `syncService.collectionIndex.live.count`), «Покупки» (бейдж — число пунктов «купить» из данных покупок; если источника нет без новых подписок — бейдж отложить и записать в задаче), «Профиль» и «Ассистент» скрыты в сайдбаре;
  - `TabSection` «Коллекции» из `RecipeFolder.sortedActive(syncService.folders)` со счётчиками `collectionIndex.countByFolder`, без «Без коллекции», скрыт в таб-баре;
  - таймеры — тот же `MobileTimerAccessoryModifier`.

  Ветка в `AppShellView.tabView` (~:690-697): iOS 26.2+ и `idiom == .pad` → `IPadAdaptiveTabView`, иначе без изменений. Зависимости в тулбаре передавать явно (plan.md, ловушка iOS 26). — `#recipes/sidebar`, `#recipes/tabs`, окно ½
- [ ] T015 [P] [US1] Вынести телефонный аватар из `RecipeScalerNative/Views/AccountView.swift` (`accountAvatar`, ~:860-871) в `RecipeScalerNative/Views/AccountAvatarView.swift`:
  - `AccountAvatarView(url: URL?, size: CGFloat)`: фото через `AuthAvatarImage`, иначе `person.circle.fill` цветом `.secondary`, обрезка кругом — ровно как сейчас;
  - `AccountView` использует его с размером 40; вид на iPhone не меняется;
  - узора, как в прототипе, нет ни на iPad, ни на iPhone (spec.md Q6, FR-005).

  Проверка — `verify-ipad-layout.sh --iphone-regression` (профиль) без отличий; логики нет, unit-тест не нужен. — `#profile/public`, `#profile/private`
- [ ] T016 [US1] Создать `RecipeScalerNative/Views/IPad/IPadSidebarProfileFooter.swift` и подключить через `.tabViewSidebarBottomBar`.
  - Аватар — `AccountAvatarView` (T015) размером 36 (`footerAvatarSize`): фото, если есть, иначе `person.circle.fill` — как в `AccountView` на iPhone.
  - Подпись: публичный профиль с именем → имя; иначе → номер аккаунта (`UserIdFormatter`, моноширинный).
  - Данные — `AccountSettingsViewModel` с `.task(id: userId)` и проверкой `userId` после `await`.
  - Тап → вкладка «Профиль».

  — `#profile/public`, `#profile/private`
- [ ] T017 [US1] «Новая коллекция» в сайдбаре: `.sectionActions` → системный алерт с `TextField` → обрезка пробелов, пустое имя не сохраняется, single-flight `isSaving` → `syncService.createFolder(name:)`. Общий помощник вынести из `CollectionsRootView.commitNewFolder` (`RecipeScalerNative/Views/CollectionsRootView.swift` ~:458-484) и использовать в обоих местах. — `#recipes/sidebar`
- [ ] T018 [P] [US1] Создать `RecipeScalerNative/Views/IPad/IPadAssistantToolbarButton.swift` (✦; в US1 открывает телефонный лист ассистента, новый чат). Покупки (`RecipeScalerNative/Views/ShoppingListView.swift`):
  - `.iPadReadableWidth(720)`;
  - «Купить во Вкусвилле» только иконкой (`AppToolbarStyle.iconOnly`), если ширина контента < 640 — только при `.padRegular`; в compact как на iPhone (`labeledIcon`, ~:704);
  - ✦ справа при `.padRegular`.

  — `#shopping/recipe`, `#shopping/az`
- [ ] T019 [P] [US1] Профиль и встряхивание.
  - `RecipeScalerNative/Views/AccountView.swift`: `.iPadReadableWidth(720)`, строка встряхивания (~:579-585) скрыта при `idiom == .pad`; строка «Аккаунт» — как на iPhone (`AccountAvatarView` из T015).
  - `RecipeScalerNative/Utils/ShakeToOpenAssistantPreference.swift`: `isActive(idiom:)`; использовать в `AppShellView` (~:205, ~:214).
  - Тесты `testPhoneHonorsPreference`, `testPadIgnoresShake` в `RecipeScalerNativeTests/ShakeToOpenAssistantPreferenceTests.swift`.

  — `#profile/public`
- [ ] T020 [P] [US1] Импорт: на iPad-симуляторе проверить, как `RecipeScalerNative/Views/ImportRecipeSheet.swift` (detents `[.large]`, ~:216) показывается в широком окне. Если не form sheet около 560 × 720 — добавить `.iPadFormSheet()` при `.padRegular`. В compact — без изменений. — `#import/text`, `#import/photo`
- [ ] T021 [US1] Подборки.
  - `RecipeScalerNative/Views/DiscoverRootView.swift`: при `.padRegular` заголовок и `DiscoverFeedSegmentPicker` (ширина 320) в одной строке вместо пикера под large title (~:29-31); лента `.iPadReadableWidth(720)`; ✦ (`IPadAssistantToolbarButton` из T018).
  - `RecipeScalerNative/Views/Discover/DiscoverPublicProfileView.swift`: `.iPadReadableWidth(1100)`, сетка `DiscoverRecipeCardGrid` как есть.

  — `#discover/feed`, `#discover/author`
- [ ] T022 [US1] Создать `RecipeScalerNativeUITests/Specs/IPadShellSpec.swift` (`XCTSkipUnless` iPad): `testSidebarContents`, `testFooterPrivateShowsAccountId`, `testProfileHasNoShakeRow`, `testCollectionTapOpensRecipes`, `testNewCollectionFromSidebar`. Прогнать на iPad; на iPhone — `AppShellNavigationSpec` и `verify-ui-smoke.sh`. — `#recipes/sidebar`, `#profile/private`

**Checkpoint (US1)**:
- iPad iPadOS 26.2+: сайдбар, верхний бар, нижний бар в ½ и ⅓ — по layout.md §Карта состояний.
- Покупки, профиль, подборки по центру; импорт в form sheet; встряхивание не работает.
- iPhone: 0 отличий скриншотов, smoke и `AppShellNavigationSpec` зелёные.
- Ручной проход человека по `#recipes/sidebar`, `#recipes/tabs`, `#shopping/*`, `#discover/*`, `#import/*`, `#profile/*`.
- Можно выпускать.

---

## Phase 4: User Story 2 — Рецепты: колонка списка и две колонки (P1)

**Goal**: список 320 pt + панель рецепта, рецепт в две колонки по ширине, кнопка «Список рецептов», контекстное меню.  
**Independent Test**: spec.md US2.

- [ ] T023 [US2] Режим колонки в `RecipeScalerNative/Views/RecipeListView.swift` (только при `.padRegular`):
  - строка выбирает рецепт через `RecipesSelection` вместо `NavigationLink(value:)` (~:535), выбранная строка выделена;
  - плитка папок (`viewModeMenu`, ~:403-435) скрыта;
  - заголовок «Все рецепты» / название коллекции; при скрытом сайдбаре (или всегда, если S2 = FAILED) — меню выбора «Все рецепты | коллекции» с галочкой;
  - поиск и меню «+» как есть.

  Тот же режим для `RecipeScalerNative/Views/CollectionFolderView.swift`. — `#recipes/sidebar`, `#recipes/tabs`, `#recipes/search`
- [ ] T024 [US2] Создать `RecipeScalerNative/Views/IPad/IPadRecipesSplitView.swift` по варианту из T006:
  - колонка списка 320 + разделитель + панель `YDocRecipeDetailView(recipeId:)` с `.id(recipeId)`;
  - ширина контента измеряется через `onGeometryChange` (iOS 18+) / `GeometryReader` (iOS 17) и передаётся в `IPadLayoutPolicy`;
  - кнопка «Список рецептов» (`sidebar.left`), если список скрыт; список поверх рецепта, если ширины не хватает;
  - флаг «список спрятан» — в `AppShellCoordinator`;
  - передавать `isSplitActive = true` в привязку `IPadShellItem` (T012), пока split показан.

  Подключить в корень вкладки «Рецепты» при `.padRegular`. — `#recipes/focus`, `#recipes/tabs`
- [ ] T025 [US2] Две колонки рецепта.
  - Создать `RecipeScalerNative/Views/YDocRecipeDetailColumns.swift`.
  - В `RecipeScalerNative/Views/YDocRecipeDetailView.swift` вынести левую колонку (фото, заголовок, порции, ингредиенты, КБЖУ, ~:280-396) и правую (`StepsSection` / `RecipeDescriptionEditorBlock`, ~:400-414) в `@ViewBuilder`.
  - Одна колонка — прежний `VStack` в прежнем порядке.
  - Две колонки (`.padRegular` и панель ≥ 720) — `HStack`: левый `ScrollView` шириной `IPadLayoutPolicy.detailLeftWidth` (T007), разделитель, правый `ScrollView` с шагами не шире 660 и отступами 32.
  - `DetailScrollViewProbe` на правой колонке, `.mobileTimerPanelBottomPadding` на обеих, `AwakeScrollChromeModifier` на внешнем контейнере.
  - Перетаскиваемый разделитель (spec.md FR-012a, plan.md Р6, Q5):
    - линия 1 pt, область захвата 12 pt (`columnDividerHitWidth`);
    - во время перетаскивания ширина живая (`@State`) и проходит через `detailLeftWidth` (упоры 320 / 480, правой ≥ 320);
    - при отпускании пишется в `@AppStorage("ipad.recipeDetailLeftColumnWidth")`; при раскладке только читается — сужение окна, список и инспектор сохранённое значение не меняют;
    - VoiceOver: «Ширина колонок» (ключ `ipad.recipe.columnDivider`), `accessibilityAdjustableAction` ±20 pt;
    - та же ширина в правке (T041).

  — `#recipes/tabs`, `#recipes/sidebar`
- [ ] T026 [US2] Варианты тулбара рецепта в `RecipeScalerNative/Views/YDocRecipeDetailView.swift` (~:825-880):
  - `.phone` — как сейчас;
  - `.padWide` (панель ≥ 600) — «…», «Поделиться», «Не гасить экран», ✦, «Изменить» с текстом;
  - `.padNarrow` — «…», «Не гасить экран», ✦, карандаш без текста.

  ✦ — `IPadAssistantToolbarButton`. Зависимости передавать явно. — `#recipes/sidebar` (узкий), `#recipes/tabs` (широкий)
- [ ] T027 [P] [US2] Контекстное меню строки в `RecipeScalerNative/Views/RecipeListView.swift` (только при `idiom == .pad`):
  - «Закрепить/Открепить», «В коллекцию», «В список покупок», «Поделиться», разделитель, «Удалить» — на тех же обработчиках, что свайпы (~:544-573);
  - «Поделиться» → `RecipeShareSheet` (вынести из `private` в `RecipeScalerNative/Views/RecipeDetailShareButton.swift`, если не хватает `isPublic` / `hasImage` / `hasSteps` у строки — пункт отложить и записать здесь, FR-017).

  — `#recipes/context`
- [ ] T028 [US2] Правила выбора.
  - Ничего не выбрано → первый рецепт списка (закреплённые сверху).
  - Удалён открытый → следующий.
  - Удалена выбранная коллекция → «Все рецепты».
  - Диплинки (`AppShellCoordinator.handleDeepLink` ~:256, Spotlight, быстрые действия) открывают рецепт в панели и выделяют строку.
  - Логика — в `RecipeScalerNative/Routing/RecipesSelection.swift`, тесты — в `RecipesSelectionTests`.

  — `#recipes/collection`
- [ ] T029 [US2] iPhone-регрессия после T023–T028: `bash scripts/verify-ipad-layout.sh --iphone-regression` (рецепт, правка, список, коллекция, поиск) — 0 отличий; `bash scripts/verify-description-editor.sh`, `bash scripts/verify-recipe-collections.sh` на iPhone — зелёные. Расхождения исправить в этой задаче. — `#recipes/sidebar`, `#recipes/collection`, `#recipes/search`, `#edit/edit` на iPhone
- [ ] T030 [US2] Создать `RecipeScalerNativeUITests/Specs/IPadRecipesSpec.swift`: `testListAndTwoColumns`, `testCollectionSelection`, `testShowListButton`, `testRotationKeepsRecipe`, `testContextMenu`, `testSearchFiltersColumn`, `testColumnDividerDragPersists` (потянуть разделитель вправо до упора → левая колонка 480 ± 1 по `frame`; `app.terminate()` + `app.launch()` с теми же аргументами → ширина та же). — `#recipes/tabs`, `#recipes/focus`, `#recipes/collection`, `#recipes/context`, `#recipes/search`
- [ ] T031 [US2] Ручной проход по layout.md §Матрица приёмки для `recipes/*`: альбомная и книжная, весь экран и ⅔, сайдбар виден и скрыт; разделитель колонок пальцем и трекпадом (упоры, сохранение после перезапуска и после сужения окна). Отметить «пройдено / не пройдено» по каждому пункту. — `#recipes/*`

**Checkpoint (US2)**: колонки и две колонки рецепта совпадают с прототипом по матрице; открытый рецепт переживает поворот и смену ширины; iPhone — 0 отличий. Можно выпускать.

---

## Phase 5: User Story 3 — Ассистент как инспектор (P2)

**Goal**: `.inspector` 340 pt из любой вкладки, история поповером, лист в compact.  
**Independent Test**: spec.md US3.

- [ ] T032 [US3] Инспектор уровня оболочки в `RecipeScalerNative/Views/AppShellView.swift`:
  - `.inspector(isPresented:)` + `.inspectorColumnWidth(340)` при `.padRegular`;
  - `AssistantSheetModifier` (~:1046-1072) получает `.constant(false)` при `.padRegular`;
  - один `showAssistant` (~:106);
  - переход sheet ↔ inspector при смене size class без потери чата (`AssistantSessionStore`).

  — `#assistant/chat`
- [ ] T033 [US3] `RecipeScalerNative/Views/AssistantSheet.swift`: режим `AssistantPresentation.inspector` — заголовок «Ассистент», группа (история, новый чат) и × (закрыть). История (~:129) открывается `.adaptivePopover` с содержимым `RecipeScalerNative/Views/AssistantThreadListSheet.swift`. В листе — как на iPhone. — `#assistant/history`, `#assistant/new`
- [ ] T034 [US3] Переключение.
  - ✦ на рецепте, «Покупках», «Подборках» и вкладка «Ассистент» верхнего бара открывают и закрывают инспектор без смены вкладки (`IPadShellItem`, T012).
  - ✦ на «Покупках» и «Подборках» открывает новый чат.
  - `IPadRecipesSplitView` учитывает инспектор в ширине контента (FR-022).

  — `#assistant/chat`, `#assistant/new`
- [ ] T035 [US3] Создать `RecipeScalerNativeUITests/Specs/IPadAssistantSpec.swift`: `testInspectorOpensFromRecipe`, `testTabSwitchKeepsInspector`, `testSizeClassSwitchKeepsChat`, `testHistoryPopover`. Ручной проход `#assistant/*` в альбомной, книжной и окне ⅓. — `#assistant/chat`, `#assistant/history`, `#assistant/new`

**Checkpoint (US3)**: инспектор открывается из любой вкладки, список прячется, рецепт остаётся в две колонки в альбомной; в compact — лист с тем же чатом; iPhone — лист как раньше, 0 отличий.

---

## Phase 6: User Story 4 — Готовка и действия (P2)

**Goal**: полоса готовки на обе колонки, «Коллекции» поповером, таймеры поповером.  
**Independent Test**: spec.md US4.

- [ ] T036 [P] [US4] Полоса готовки и управление без рук в двух колонках.
  - `ScreenAwakeStatusBanner` стоит под тулбаром на всю ширину панели (проверить `RecipeScalerNative/Views/AwakeScrollChromeModifier.swift` с раскладкой T025).
  - Команды прокрутки двигают правую колонку (`DetailScrollViewProbe`).
  - Прогнать `RecipeScalerNativeTests/AwakeScrollControllerTests` и `AwakeScrollEngineTests`.

  — `#recipes/cooking`
- [ ] T037 [P] [US4] «Коллекции» поповером: `RecipeScalerNative/Views/RecipeDetailActionsMenu.swift` (~:61-62) — `.adaptivePopover` вместо `.sheet` при `.padRegular`; `RecipeScalerNative/Views/CollectionAssignSheet.swift` — ширина 300 в поповере, сохранение при закрытии как сейчас (~:112-114). Добавить `testCollectionsPopoverPersists` в `IPadRecipesSpec`. — `#recipes/collections`
- [ ] T038 [US4] Таймеры поповером по вердикту S6.
  - Тап по капсуле `tabViewBottomAccessory` при `.padRegular` открывает поповер 380 pt с `MobileTimerPanel` вместо раскрытой панели (`RecipeScalerNative/Views/AppShellView.swift` ~:650-664).
  - Если аксессуара в режиме сайдбара нет — своя капсула `.overlay(alignment: .bottom)` в `IPadAdaptiveTabView`.
  - Содержимое панели не меняется («Сбросить все» не добавляем).

  — `#recipes/timers`
- [ ] T039 [US4] Проверить таблицу готовки (`RecipeScalerNative/Views/Cooking/ProcessTableCookingPresenter.swift`, ветки по idiom ~:55-120; `ProcessTableCookingOrientationGate.swift`) на iPad в обеих ориентациях и в окне ½. Исправлять, только если на iPad есть принудительный поворот или обрезка. — `#recipes/cooking`
- [ ] T040 [US4] Ручной проход `#recipes/cooking`, `#recipes/collections`, `#recipes/timers` в альбомной (две колонки), книжной и ½. `bash scripts/verify-timer-widget.sh` на iPhone — зелёный. — `#recipes/cooking`, `#recipes/collections`, `#recipes/timers`

**Checkpoint (US4)**: полоса готовки на обе колонки, поповеры «Коллекции» и таймеров в широком окне, листы в compact; iPhone без изменений.

---

## Phase 7: User Story 5 — Правка в две колонки (P2)

**Goal**: правка на всю ширину раздела, «Готово» над шагами, панель форматирования под шагами.  
**Independent Test**: spec.md US5.

- [ ] T041 [US5] Вход в правку при `.padRegular`:
  - `IPadRecipesSplitView` прячет список (`isEditing` в `IPadLayoutPolicy`), сайдбар сворачивается, если S2 = VERIFIED;
  - правка раскладывается колонками T025 (тот же разделитель и сохранённая ширина): слева шапка правки, порции, `YDocIngredientsEditSection`, справа `RecipeDescriptionEditorBlock`.

  — `#edit/edit`
- [ ] T042 [US5] Расположение элементов правки в две колонки.
  - Над правой колонкой только «Готово», как на iPhone (spec.md Q2; на iPhone — тулбар как сейчас, `YDocRecipeDetailView.swift` ~:850).
  - `formattingBarInset` (~:505-507, ~:776-789) через `.safeAreaInset(edge: .bottom)` правого `ScrollView`.
  - Проверить аппаратную и плавающую клавиатуру: курсор не уходит под клавиатуру, панель видна.

  — `#edit/edit`
- [ ] T043 [US5] После «Готово» рецепт открыт, список скрыт, кнопка «Список рецептов» есть (как `#recipes/focus`). Смена size class во время правки сохраняет фокус и текст. Одна колонка правки при панели < 720 — не шире 720 по центру. — `#edit/edit` → `#recipes/focus`
- [ ] T044 [US5] Тест `testEditTwoColumns` в `RecipeScalerNativeUITests/Specs/IPadRecipesSpec.swift`; `bash scripts/verify-description-editor.sh` на iPhone; ручной проход `#edit/edit` в альбомной, ⅔ и ½. — `#edit/edit`

**Checkpoint (US5)**: правка в две колонки совпадает с прототипом; на iPhone правка без изменений (0 отличий скриншотов).

---

## Phase 8: User Story 6 — Клавиатура и меню-бар (P3)

**Goal**: команды из layout.md §Меню в меню-баре и по шорткатам.  
**Independent Test**: spec.md US6.

- [ ] T045 [US6] Создать `RecipeScalerNative/Views/IPad/IPadCommands.swift`: `FocusedValueKey` для `AppCommandActions` (вкладки, ассистент, новый рецепт, импорт, новая коллекция, поиск, сайдбар) и `RecipeCommandActions` (правка, порции, покупки, закрепить, коллекции, не гасить экран, удалить, поделиться). Публиковать через `.focusedSceneValue` из `AppShellView` и `YDocRecipeDetailView` **только при `idiom == .pad`**. — `#menubar/file`, `#menubar/recipe`, `#menubar/view`
- [ ] T046 [US6] `.commands` на `WindowGroup` в `RecipeScalerNative/RecipeScalerNativeApp.swift` (~:176):
  - «Файл» (`CommandGroup(after: .newItem)`), «Рецепт» (`CommandMenu`), «Вид» (`CommandGroup(before: .sidebar)` / `.toolbar`);
  - шорткаты по таблице layout.md §Меню;
  - в меню только действия, которые есть на iPhone: «Экспорт в PDF…» прототипа не добавляется (spec.md Q3);
  - строки — ключи `ipad.menu.*` в `RecipeScalerNative/Resources/Localizable.xcstrings`.

  — `#menubar/file`, `#menubar/recipe`, `#menubar/view`
- [ ] T047 [US6] ⌘↩ на «Готово» правки и ⌘F → `.searchFocused` колонки списка (iOS 18+; на 17 пункта нет). Проверить, что на iPhone с клавиатурой ничего нового не срабатывает. — `#edit/edit`, `#recipes/search`
- [ ] T048 [US6] Создать `RecipeScalerNativeUITests/Specs/IPadKeyboardSpec.swift` (`XCUIElement.typeKey`): ⌘E, ⌘↩, ⌘+, ⌘−, ⌘0, ⇧⌘L, ⇧⌘P, ⌃⌘A, ⌘⌫ (появляется подтверждение удаления, тест его отменяет), ⌘1–⌘4, ⌘J, ⌘F, ⌘N, ⇧⌘I, ⇧⌘N; меню «Рецепт» неактивно без рецепта. — `#menubar/recipe`

**Checkpoint (US6)**: все шорткаты срабатывают на iPad-симуляторе с аппаратной клавиатурой (SC-006); на iPhone поведение прежнее.

---

## Phase 9: User Story 7 — Многозадачность и окна (P3)

**Goal**: вся матрица ширин без потерь состояния; решение по нескольким окнам.  
**Independent Test**: spec.md US7.

- [ ] T049 [US7] Матрица ширин.
  - Добавить в `scripts/verify-ipad-layout.sh` проход по layout.md §Матрица приёмки через `-DebugWindowWidth`.
  - Вручную проверить на симуляторе Split View (½, ⅔, ⅓), Slide Over и Stage Manager с непрерывным изменением размера: нет белых экранов и мигания, рецепт и коллекция сохраняются.

  — все 24 состояния, `#recipes/sidebar` … `#menubar/view` (layout.md §Карта состояний), окна ⅔ / ½ / ⅓ (layout.md §Матрица приёмки)
- [ ] T050 [US7] Решение по нескольким окнам по вердикту S7 из T005 (Q4).
  - По умолчанию — одно окно: `UIApplicationSupportsMultipleScenes` не добавляется.
  - Запись в `docs/DECISIONS.md` с причиной (общий `AppContainer` и `DeepLinkRouter.shared`) и ссылкой на будущую спеку.

  — `#menubar/file` («Закрыть окно» без второго окна), `.other-win` прототипа не делаем
- [ ] T051 [US7] Старый путь iPadOS 17.0–26.1 (spec.md Q1: на 17 API сайдбара нет, на 18–26.1 — общий гейт оболочки 26.2; расширение на 18+ — на потом).
  - Создать iPad-симулятор на iOS 18.4 (`xcrun simctl create … com.apple.CoreSimulator.SimRuntime.iOS-18-4`) и проверить iPad без сайдбара: системный таб-бар, колонки рецепта, инспектор, поповеры, form sheet.
  - Капсулы таймеров нет.
  - iOS 17 — если runtime доступен, иначе отметить как непроверенное.

  — `#recipes/tabs`, `#assistant/chat`
- [ ] T052 [US7] Исправить найденные в T049–T051 переходы. Повторить матрицу. — строки `#recipes/tabs`, `#assistant/chat`, `#shopping/recipe` из layout.md §Матрица приёмки, упавшие в T049

**Checkpoint (US7)**: SC-005 — 100% проверок матрицы сохраняют рецепт и коллекцию; решение по окнам записано.

---

## Phase 10: Polish

- [ ] T053 [P] Строки: все новые ключи en + ru в `RecipeScalerNative/Resources/Localizable.xcstrings`, телефонные ключи переиспользованы (FR-032); `bash scripts/lint-i18n.sh`, `RecipeScalerNativeTests/LocalizationConsistencyTests`. Проверить русский и английский интерфейс на iPad. — `#recipes/sidebar`, `#menubar/file`, `#menubar/recipe`, `#menubar/view`, `#profile/private`
- [ ] T054 [P] Документация:
  - `docs/DECISIONS.md` — оболочка iPad, старый путь (Q1, сайдбар на 18+ — на потом), колонки (вариант A/B), перетаскиваемый разделитель и его ключ `UserDefaults` (Q5), окна (Q4);
  - `docs/AGENT-WORKFLOW.md` — `resolve-ipad-simulator.sh`, `verify-ipad-layout.sh`;
  - `docs/PRD.md` — снять «только iPhone» (~:26, ~:544);
  - отметить, что эта спека заменяет невлитые `specs/062-mac-ipad-layout` (ветка `043-mac-ipad-layout`) и `specs/063-ipad` (ветка `063-ipad-adaptation`) для iPad.

  — `#recipes/sidebar`, `#recipes/tabs` (разделитель колонок), `#menubar/view` (решения, которые фиксирует документация)
- [ ] T055 [P] iPad-скриншоты App Store: `scripts/capture-app-store-screenshots.sh` и `scripts/validate-app-store-screenshots.sh` для iPad 13″ (2064 × 2752, обе ориентации по требованиям ASC). **Human gate**: загрузка и выбор доступности на Mac и Vision Pro в ASC. — `#recipes/tabs`, `#assistant/chat`, `#shopping/recipe`
- [ ] T056 Полная проверка по plan.md §Verification:
  - `bash scripts/verify-all.sh`;
  - iPhone-регрессия;
  - все iPad UI-спеки;
  - `verify-ipad-layout.sh` с ручной сверкой со скриншотами прототипа.

  — все 24 состояния, `#recipes/sidebar` … `#menubar/view` (layout.md §Карта состояний)
- [ ] T057 Независимое ревью отдельным агентом (не self-review) по plan.md: инварианты iPhone, ловушка environment в тулбарах, утечки стеков в `TabSection`, async lifecycle футера. — все 24 состояния, `#recipes/sidebar` … `#menubar/view` (layout.md §Карта состояний)

**Checkpoint (Polish)**: `verify-all.sh` зелёный, ревью без блокирующих замечаний, human gates отмечены.

---

## Dependencies & Execution Order

- **Setup (T001–T004)** → **Foundational (T005–T011)** → истории.
- **T005, T006** блокируют всю вёрстку. T007, T008, T010, T011 можно делать параллельно со спайком, T009 — после T008.
- **US1 (T012–T022)** блокирует остальные истории.
  - Внутри: T012 → T013 → T014 → (T016, T017); T015 → T016; T015 → T019 (оба трогают `AccountView` / `AccountAvatarView`); T018–T020 параллельно после T014; T021 после T018; T022 последней.
- **US2 (T023–T031)** после US1.
  - T023 → T024 → T025 → T026; T027 параллельно с T025; T028 после T024; T029 после T023–T028. Разделитель T025 опирается на `detailLeftWidth` из T007.
- **US3, US4, US5** после US2, независимы друг от друга.
  - US5 использует колонки из T025.
  - US3 T034 трогает `IPadRecipesSplitView` после T024.
- **US6** после US1–US5 (публикует их действия). **US7**: T049 и T051 — после US3 и US4 (матрица и старый путь проверяют инспектор, поповеры и капсулу таймеров); T050 — после T005; T052 — после T049–T051.
- **Polish** последней.

## Phase summary

| Фаза | Задачи | Количество |
|------|--------|-----------|
| 1 Setup | T001–T004 | 4 |
| 2 Foundational | T005–T011 | 7 |
| 3 US1 Оболочка (P1) | T012–T022 | 11 |
| 4 US2 Рецепты (P1) | T023–T031 | 9 |
| 5 US3 Ассистент (P2) | T032–T035 | 4 |
| 6 US4 Готовка и действия (P2) | T036–T040 | 5 |
| 7 US5 Правка (P2) | T041–T044 | 4 |
| 8 US6 Клавиатура и меню (P3) | T045–T048 | 4 |
| 9 US7 Многозадачность (P3) | T049–T052 | 4 |
| 10 Polish | T053–T057 | 5 |
| **Всего** | | **57** |
