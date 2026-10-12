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
- [x] T003 В `RecipeScalerNative.xcodeproj/project.pbxproj` поставить `TARGETED_DEVICE_FAMILY = "1,2"` для таргета `RecipeScalerNative` во всех конфигурациях (строки ~4158, ~4397, ~4419, ~4442).
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

- [x] T005 Спайк оболочки в отдельной временной ветке (код спайка не вливается). Проверить на iPad-симуляторе iPadOS 26.x пункты из plan.md §Результаты спайка:
  - **S1** — `TabView(.sidebarAdaptable)` + `TabSection` с динамическими коллекциями + `.sectionActions` + `.tabViewSidebarBottomBar`: без белого экрана, всё кликается;
  - **S2** — чтение и управление видимостью сайдбара;
  - **S3** — compact даёт нижний таб-бар, как `modernTabView`;
  - **S7** — оценка нескольких окон: можно ли держать `AppShellCoordinator` на сцену при общем `AppContainer` (`RecipeScalerNative/RecipeScalerNativeApp.swift:121`, `RecipeScalerNative/App/AppContainer.swift:65`) и что делать с `DeepLinkRouter.shared`.

  Заполнить вердикты в plan.md. При белом экране или некликабельности — STOP 2. — `#recipes/sidebar`, `#recipes/tabs`, окно ½

  **Сделано 2026-10-12** — `tmp/ipad-research/spike-verdicts.md`, plan.md §Результаты спайка. S1 VERIFIED с обходами, S2 CHECKED (ландшафт INCONCLUSIVE), S3 VERIFIED с обходом, S7 FAILED (дорого) → STOP 5.
- [x] T006 Спайк контента (та же временная ветка):
  - **S4** — вариант A (`NavigationSplitView` из двух колонок внутри `Tab`) против B (`HStack` из двух `NavigationStack`): тулбары обеих колонок, `.searchable` в колонке списка, список поверх рецепта;
  - **S5** — `.inspector` на уровне `TabView`, ширина 340, переход sheet ↔ inspector при смене size class с открытым чатом;
  - **S6** — `.popover` от пункта `Menu` и от `tabViewBottomAccessory`; есть ли аксессуар в режиме сайдбара.

  Записать выбор варианта A/B в plan.md (Р5) и в `docs/DECISIONS.md`. Если ломаются оба — STOP 3. — `#recipes/focus`, `#assistant/chat`, `#recipes/collections`, `#recipes/timers`

  **Сделано 2026-10-12** — `tmp/ipad-research/spike-verdicts.md`, plan.md §Результаты спайка. S4: A FAILED, B VERIFIED → Р5 = B. S5: `.inspector` на `TabView` FAILED (STOP 2) → своя панель 340 + лист (Р7). S6 VERIFIED с обходом (поповер таймеров на уровне оболочки). Решения — `docs/DECISIONS.md` 2026-10-12.

### Основы

- [x] T007 [P] Создать `RecipeScalerNative/Views/IPad/IPadLayoutPolicy.swift`:
  - `IPadLayoutMetrics` — все константы из layout.md §Токены;
  - чистая `IPadLayoutPolicy.resolve(contentWidth:listCollapsedByUser:isEditing:) -> IPadLayout` (`listShown`, `detailWidth`, `twoColumns`, `toolbarStyle`, `showsListButton`, `shopVkusvillIconOnly`);
  - чистая `IPadLayoutPolicy.detailLeftWidth(preferred: CGFloat?, detailWidth:) -> CGFloat?` — формула `leftWidth` из layout.md §Токены; `nil` при одной колонке.

  Создать `RecipeScalerNativeTests/IPadLayoutPolicyTests.swift`:
  - каждый порог (560+321, 720, 600, 640) на значении и на 1 pt ниже;
  - `testPrototypeMatrix` — все строки layout.md §Матрица приёмки;
  - `testLeftColumnClamp`: без сохранённой ширины — 400; 200 → 320; 600 → 480; панель 720 → не шире 399, панель 760 → не шире 439 (правой ≥ 320); панель 719 → `nil`.

  — `#recipes/sidebar`, `#recipes/tabs`, `#assistant/chat`
- [x] T008 [P] Создать `RecipeScalerNative/Views/IPad/AppLayoutMode.swift`:
  - `enum AppLayoutMode { case phone, padRegular }`;
  - `EnvironmentValues.appLayoutMode`, по умолчанию `.phone`;
  - чистая `AppLayoutMode.resolve(idiom:horizontalSizeClass:)`.

  Подключить в `RecipeScalerNative/ContentView.swift` (`rootChrome`, ~:192-210). Создать `RecipeScalerNativeTests/AppLayoutModeTests.swift` (`testPhoneIdiomIsAlwaysPhone`, `testPadCompactIsPhone`, `testPadRegularIsPadRegular`). — `#recipes/tabs` в окне ½ против всего экрана
- [x] T009 Перевести `AppShellCoordinator.recipesPath` с `NavigationPath` на `[RecipesRoute]` (`RecipeScalerNative/Routing/AppShellCoordinator.swift:68`).
  - Обновить привязки в `RecipeScalerNative/Views/RecipeListView.swift` (:18, :40 и места использования), `RecipeScalerNative/Views/CollectionsRootView.swift`, `RecipeScalerNative/Views/CollectionFolderView.swift`, `RecipeScalerNative/Views/AppShellView.swift` (~:724, ~:805).
  - Убедиться, что путь нигде не сериализуется (`NavigationPath.CodableRepresentation`).
  - Создать `RecipeScalerNative/Routing/RecipesSelection.swift` (путь ↔ выбор, plan.md Р4) и `RecipeScalerNativeTests/RecipesSelectionTests.swift`: `testPathRoundTrip`, `testSelectingCollectionOpensFirstRecipe`, `testSelectionSurvivesModeSwitch`, `testDeletedSelectionFallsBack`.
  - Прогнать `RecipeScalerNativeTests/AppShellCoordinatorTests` и `verify-ipad-layout.sh --iphone-regression`.

  — `#recipes/collection`
- [x] T010 [P] Создать `RecipeScalerNative/Views/IPad/AdaptivePresentation.swift`:
  - `.adaptivePopover(isPresented:arrowEdge:content:)` — при `.phone` ровно существующий `.sheet` с `appOpaqueSheetPresentation()` (`RecipeScalerNative/Utils/AppSheetChrome.swift`);
  - `.iPadReadableWidth(_:)` через `.contentMargins` / `frame(maxWidth:)` — при `.phone` без эффекта;
  - `.iPadFormSheet()` — `.presentationSizing(.form)` на iOS 18+.

  `#Preview` для обоих режимов. — `#recipes/collections`, `#shopping/recipe`, `#import/text`
- [x] T011 [P] Идентификаторы и DEBUG-аргументы.
  - Добавить идентификаторы сайдбара, футера, коллекций сайдбара, колонки списка, кнопки «Список рецептов», инспектора, ✦ в `RecipeScalerNative/AccessibilityIdentifiers.swift` и `RecipeScalerNativeUITests/Helpers/Selectors.swift`.
  - Добавить DEBUG-аргументы `-IPadSidebarHidden`, `-IPadListHidden`, `-DebugWindowWidth <pt>` в `RecipeScalerNative/Utils/DebugLaunchOptions.swift` (только `#if DEBUG`; `-DebugWindowWidth` сужает корневой контейнер и подменяет `horizontalSizeClass` — для матрицы политики, не для системных переходов).
  - Расширить `scripts/verify-ipad-layout.sh` (T002): состояния со скрытым сайдбаром и скрытым списком через `-IPadSidebarHidden` / `-IPadListHidden`. Матрицу окон добавит T049.

  — `#recipes/tabs`, `#recipes/focus`

**Checkpoint**: вердикты S1–S7 записаны, вариант колонок выбран (B), ассистент — своя панель, одно окно (STOP 5). `IPadLayoutPolicyTests`, `AppLayoutModeTests`, `RecipesSelectionTests`, `AppShellCoordinatorTests` зелёные. `verify-ipad-layout.sh --iphone-regression` — 0 отличий. iPad-ветки ещё не видны пользователю.

---

## Phase 3: User Story 1 — Нативная оболочка iPad (P1) — MVP

**Goal**: сайдбар, верхний и нижний таб-бары, телефонные экраны по центру, профиль «Моё всё» листом в широком окне (Q7), импорт в form sheet, без встряхивания.  
**Independent Test**: spec.md US1.

- [x] T012 [US1] Создать `RecipeScalerNative/Views/IPad/IPadShellItem.swift`:
  - `enum IPadShellItem { case tab(AppTab), collection(String) }`;
  - вычисляемая привязка поверх `coordinator.selectedTab` и `coordinator.recipesPath` (plan.md Р2), перехват `.tab(.assistant)`;
  - чтение принимает плейсмент (`@Environment(\.tabBarPlacement)`, plan.md Р2): `.collection(id)` отдаётся `TabView` только при `.sidebar`; при `.topBar` и в compact выбранная коллекция читается как `.tab(.recipes)`, папка остаётся в пути (спайк S1 обход 4: иначе в верхний бар вылезает вся группа «Коллекции»);
  - запись `.collection(id)` зависит от параметра `isSplitActive`: `false` (US1, compact, телефонный стек) → путь `[.folder(id)]`, телефонный экран коллекции; `true` (активен `IPadRecipesSplitView`, включает T024) → `[.folder(id), .recipe(первый рецепт, folderContext: id)]`, пустая коллекция → `[.folder(id)]`.

  Создать `RecipeScalerNativeTests/IPadShellItemTests.swift` (`testAssistantDoesNotChangeSelection`, `testCollectionMapsToRecipesPath` — оба случая `isSplitActive`, `testDeepLinkPathMapsToCollection`, `testCollectionInTopBarMapsToRecipesTab`). — `#recipes/sidebar`, `#recipes/collection`
- [x] T013 [US1] Вынести корни вкладок из `modernTabBar` (`RecipeScalerNative/Views/AppShellView.swift` ~:709-770) в `RecipeScalerNative/Views/AppShellTabRoots.swift`. Только перенос: iPhone-дерево не меняется. Проверка — `verify-ipad-layout.sh --iphone-regression` и `AppShellNavigationSpec` на iPhone. — `#recipes/tabs` на iPhone (рефакторинг, вид не меняется)

  **Проверено:** `--iphone-regression` — 11 состояний, 0 отличий (`recipes-list` и `assistant-chat` сошлись со второй попытки скрипта). `AppShellNavigationSpec` собирается, но 3 теста пропущены: нет бэкенда для `register-auto` (127.0.0.1:3001).
- [x] T014 [US1] Создать `RecipeScalerNative/Views/IPad/IPadAdaptiveTabView.swift`.

  **Первый шаг — проверка, не подтверждённая спайком** (plan.md §Непроверенное): «Профиль» и «Ассистент» с `.tabPlacement(.pinned)` + динамическим `.defaultVisibility(placement == .sidebar ? .hidden : .automatic, for: .sidebar)`. Переключить сайдбар туда и обратно на iPad-симуляторе: строк нет в сайдбаре, иконки у правого края верхнего бара есть. Если не работает — остановиться и спросить (строки рядом с футером или другой обход). Результат записать в задаче.

  **Результат проверки (iPad Pro 11" M4, iPadOS 26.3, портрет): работает.** Сайдбар показан — строк «Профиль» и «Ассистент» нет ни сверху, ни после «Коллекций» (прокрутка до конца); сайдбар скрыт — `tab_profile` и `tab_assistant` иконками у правого края верхнего бара. Три цикла показать/скрыть, `tabBarPlacement` переключался каждый раз (7 переходов `sidebarShown` в логе). Скриншоты `tmp/ipad-verify/us1/check-*.png`.

  - `TabView(selection:)` + `.tabViewStyle(.sidebarAdaptable)`;
  - вкладки «Подборки», «Рецепты» (счётчик `syncService.collectionIndex.live.count`), «Покупки» (бейдж — число пунктов «купить» из данных покупок; если источника нет без новых подписок — бейдж отложить и записать в задаче);
  - бейджи (счётчики вкладок и коллекций) — **только при плейсменте `.sidebar`**: иначе они попадают в верхний бар (спайк S1, `s1-11`/`s1-12`);
  - «Профиль» и «Ассистент» — `.tabPlacement(.pinned)` (иконки без подписи у правого края верхнего бара) + `.defaultVisibility(sidebarShown ? .hidden : .automatic, for: .sidebar)`, `sidebarShown` — из `@Environment(\.tabBarPlacement) == .sidebar` на странице вкладки (plan.md Р2, образец Scrapp `RootView.swift:240-244`, `:311-327`); просто `.hidden` прячет вкладку и из верхнего бара;
  - содержимое `Tab` «Профиль»: в `.phone` (compact) — телефонный `AccountView` из `AppShellTabRoots`, в `.padRegular` — `Color.clear` (там профиль — лист, T019a);
  - `TabSection` «Коллекции» из `RecipeFolder.sortedActive(syncService.folders)` со счётчиками `collectionIndex.countByFolder`, без «Без коллекции», скрыт в таб-баре; **в compact (`horizontalSizeClass == .compact`) секция не строится** — иначе коллекции и Ассистент уходят в «Ещё» (S3); `traitOverrides` не помогают;
  - таймеры — тот же `MobileTimerAccessoryModifier` (аксессуар есть и в режиме сайдбара, S6);
  - **без `.inspector` на `TabView`** — он обнуляет верхний safe area вкладок (S5, STOP 2); ассистент — своя панель (T032);
  - создать `RecipeScalerNative/Views/IPad/IPadSidebarControl.swift` (plan.md Р2): «сайдбар плавает» (левый safe area страницы < 60) и `sidebar.isHidden` через `TabBarDiscovery`; только `.padRegular` и 26.2+; контроллер не найден → лог и ничего.

  Ветка в `AppShellView.tabView` (~:690-697): iOS 26.2+ и `idiom == .pad` → `IPadAdaptiveTabView`, иначе без изменений. Зависимости в тулбаре передавать явно (plan.md, ловушка iOS 26). Тесты в `IPadShellSpec` (T022): `testTopBarHasNoBadges`, `testCompactHasNoMoreTab`. — `#recipes/sidebar`, `#recipes/tabs`, окно ½

  **Сделано и проверено (iPad Pro 11", портрет):** сайдбар — «Рецепты» 69, «Покупки» 11, коллекции со счётчиками, строк «Профиль»/«Ассистент» нет; верхний бар — без бейджей, иконки профиля и ✦ справа; тап по коллекции → экран коллекции в стеке, в сайдбаре подсвечена коллекция; ✦ открывает лист ассистента, выбор не меняется; `-DebugWindowWidth=375` — нижний бар из 5 вкладок без «Ещё», «Профиль» — телефонная страница. Бейдж «Покупок» — число некупленных пунктов `syncService.shoppingSnapshot` (документ грузится с сессией, новых подписок нет). Скриншоты `tmp/ipad-verify/us1/t014-*.png`.

  **Отклонение:** секция «Коллекции» строится только при показанном сайдбаре (`sidebarShown && !isCompact`), а не всегда в regular. Плавающий сайдбар в портрете сам закрывается после тапа по коллекции, и выбранная в этот момент коллекция навсегда оставалась в верхнем баре (кнопка «›», страница с «🎂 Десерты»); чтение `.tab(.recipes)` из T012 этого не исправляло. Без секции в режиме верхнего бара коллекции в бар не попадают; при открытии сайдбара секция на месте, выбранная коллекция подсвечена.
- [x] T015 [P] [US1] Вынести телефонный аватар из `RecipeScalerNative/Views/AccountView.swift` (`accountAvatar`, ~:860-871) в `RecipeScalerNative/Views/AccountAvatarView.swift`:
  - `AccountAvatarView(url: URL?, size: CGFloat)`: фото через `AuthAvatarImage`, иначе `person.circle.fill` цветом `.secondary`, обрезка кругом — ровно как сейчас;
  - `AccountView` использует его с размером 40; вид на iPhone не меняется;
  - узора, как в прототипе, нет ни на iPad, ни на iPhone (spec.md Q6, FR-005).

  Проверка — `verify-ipad-layout.sh --iphone-regression` (профиль) без отличий; логики нет, unit-тест не нужен. — `#profile/public`, `#profile/private`

  **Проверено:** `--iphone-regression --only profile-public` — 0 отличий.
- [x] T016 [US1] Создать `RecipeScalerNative/Views/IPad/IPadSidebarProfileFooter.swift` и подключить через `.tabViewSidebarBottomBar` только при `.padRegular` (образец — `SidebarProfileRow`, Scrapp `RootView.swift:329-362`).
  - `Button` во всю ширину строки, `.hoverEffect`, идентификатор футера из T011; выбранным не бывает.
  - Аватар — `AccountAvatarView` (T015) размером 36 (`footerAvatarSize`): фото, если есть, иначе `person.circle.fill` — как в `AccountView` на iPhone.
  - Подпись: публичный профиль с именем → имя; иначе → номер аккаунта (`UserIdFormatter`, моноширинный).
  - Данные — `AccountSettingsViewModel` с `.task(id: FooterKey(userId, coordinator.profileSheetRevision))` и проверкой `userId` после `await`: после закрытия листа футер перечитывает профиль (plan.md Р2a, §Async lifecycle).
  - Тап → `coordinator.presentProfileSheet()` (лист — T019a); выбранный раздел сайдбара не меняется. Выбор из футера не закрывает плавающий сайдбар (S1 обход 3): если сайдбар плавает поверх контента — спрятать его через `IPadSidebarControl` (T014) до показа листа.
  - Зависимости передавать явно (ловушка iOS 26).

  — `#profile/public`, `#profile/private`

  **Сделано:** футер в сайдбаре — `person.circle.fill` 36 и номер аккаунта моноширинным (DEBUG-аккаунт приватный); тап прячет плавающий сайдбар. В координатор добавлены `isProfileSheetPresented`, `profileSheetRevision`, `presentProfileSheet()`; сам лист и увеличение `profileSheetRevision` при закрытии — T019a. Скриншот `tmp/ipad-verify/us1/t016-01-sidebar-footer.png`.
- [ ] T017 [US1] «Новая коллекция» в сайдбаре: `.sectionActions` → системный алерт с `TextField` → обрезка пробелов, пустое имя не сохраняется, single-flight `isSaving` → `syncService.createFolder(name:)`. Общий помощник вынести из `CollectionsRootView.commitNewFolder` (`RecipeScalerNative/Views/CollectionsRootView.swift` ~:458-484) и использовать в обоих местах. — `#recipes/sidebar`
- [ ] T018 [P] [US1] Создать `RecipeScalerNative/Views/IPad/IPadAssistantToolbarButton.swift` (✦; в US1 открывает телефонный лист ассистента, новый чат). Покупки (`RecipeScalerNative/Views/ShoppingListView.swift`):
  - `.iPadReadableWidth(720)`;
  - «Купить во Вкусвилле» только иконкой (`AppToolbarStyle.iconOnly`), если ширина контента < 640 — только при `.padRegular`; в compact как на iPhone (`labeledIcon`, ~:704);
  - ✦ справа при `.padRegular`.

  — `#shopping/recipe`, `#shopping/az`
- [ ] T019 [P] [US1] Профиль и встряхивание.
  - `RecipeScalerNative/Views/AccountView.swift`: строка встряхивания (~:579-585) скрыта при `idiom == .pad` (в листе и во вкладке compact); строка «Аккаунт» — как на iPhone (`AccountAvatarView` из T015). Ограничение ширины не ставить: в `.padRegular` профиль — лист (T019a), в compact — телефонная страница.
  - `RecipeScalerNative/Utils/ShakeToOpenAssistantPreference.swift`: `isActive(idiom:)`; использовать в `AppShellView` (~:205, ~:214).
  - Тесты `testPhoneHonorsPreference`, `testPadIgnoresShake` в `RecipeScalerNativeTests/ShakeToOpenAssistantPreferenceTests.swift`.

  — `#profile/public`
- [ ] T019a [US1] Профиль «Моё всё» — form sheet в широком окне (spec.md Q7, FR-004a, FR-004b; plan.md Р2a; образец — Scrapp `RootView.swift:55`, `:113-137`, `:163-178`).
  - Создать `RecipeScalerNative/Routing/IPadProfileSheetPolicy.swift`: чистая `resolve(selected:previous:layoutMode:) -> (selected, presentsSheet)` — `.profile` в `.padRegular` → (`previous ?? .recipes`, `true`), иначе без изменений.
  - `RecipeScalerNative/Routing/AppShellCoordinator.swift`:
    - `isProfileSheetPresented`, `lastNonProfileTab` (по умолчанию `.recipes`), `profileSheetRevision`;
    - `presentProfileSheet()`, `profileSheetDidDismiss()`, `normalizeProfileSelection(previous:layoutMode:)`;
    - сброс листа и `lastNonProfileTab` в `resetShellStateForLogout` (~:461).
  - `IPadShellItem` (T012): запись `.tab(.profile)` в `.padRegular` → `presentProfileSheet()`, `selectedTab` не меняется.
  - `IPadAdaptiveTabView` (T014) и `legacyTabView` в `RecipeScalerNative/Views/AppShellView.swift` (~:790, только при `.padRegular`, старый путь Q1):
    - `.onChange(of: coordinator.selectedTab)` → нормализация с `previous: old` (тап по вкладке, `requestRemindersSetup` ~:203-206, ⌘4, `-OpenTab=profile`);
    - `.onChange(of: layoutMode, initial: true)` → при `.padRegular` нормализация с `previous: lastNonProfileTab`; при `.phone` лист не трогать (остаётся, как в Scrapp).
  - «Профиль» в верхнем баре — `.pinned`-иконка (T014); в сайдбаре вкладки «Профиль» нет, вход — футер (T016, прячет плавающий сайдбар перед листом).
  - На симуляторе проверить урок Scrapp (`RootView.swift:113-114`): если отказ в привязке оставляет на экране пустую страницу «Профиля», привязка пропускает выбор, а `onChange` его возвращает. Записать, какой вариант остался.
  - Лист: `.sheet(isPresented: $coordinator.isProfileSheetPresented, onDismiss: profileSheetDidDismiss)` → `AccountView(…, onDone:)` + `.iPadFormSheet()` (`RecipeScalerNative/Views/IPad/AdaptivePresentation.swift`).
    - Второй `NavigationStack` не добавлять: у `AccountView` свой (`:113`) и заголовок «Моё всё» (`account.title`, `:172`).
  - `RecipeScalerNative/Views/AccountView.swift`:
    - необязательный `onDone: (() -> Void)?` → `ToolbarItem(placement: .confirmationAction) { Button("common.done") }`; на iPhone и во вкладке `nil`, дерево не меняется;
    - `pendingRemindersSetup` обрабатывается и при появлении листа (`onChange(…, initial: true)` или `.task`), поведение на iPhone прежнее.
  - Идентификатор кнопки «Готово» листа — в `RecipeScalerNative/AccessibilityIdentifiers.swift` и `RecipeScalerNativeUITests/Helpers/Selectors.swift`.
  - Тесты:
    - создать `RecipeScalerNativeTests/IPadProfileSheetPolicyTests.swift`: `testRegularProfilePresentsSheetAndKeepsPrevious`, `testRegularProfileWithoutPreviousFallsBackToRecipes`, `testPhoneProfileSelectsTab`, `testNonProfileSelectionUnchanged`;
    - в `RecipeScalerNativeTests/AppShellCoordinatorTests.swift`: `testWideningOnProfileTabRestoresPreviousAndPresentsSheet`, `testNarrowingKeepsProfileSheet`, `testRemindersSetupInRegularPresentsSheet`, `testLogoutDismissesProfileSheet`;
    - в `RecipeScalerNativeTests/IPadShellItemTests.swift`: `testProfileInRegularDoesNotChangeSelection`.
  - `scripts/verify-ipad-layout.sh`: состояния `profile-public` / `profile-private` — лист поверх `#recipes/sidebar` и (с `-IPadSidebarHidden=1`) `#recipes/tabs` через `-OpenTab=profile`; в окне ½ — страница вкладки.
  - iPhone: `verify-ipad-layout.sh --iphone-regression` (профиль) — 0 отличий.

  — `#profile/public`, `#profile/private` (`b4-profile-public-landscape`, `b4-profile-private-sidebar-hidden`, `b4-profile-window-half`)
- [ ] T020 [P] [US1] Импорт: на iPad-симуляторе проверить, как `RecipeScalerNative/Views/ImportRecipeSheet.swift` (detents `[.large]`, ~:216) показывается в широком окне. Если не form sheet около 560 × 720 — добавить `.iPadFormSheet()` при `.padRegular`. В compact — без изменений. — `#import/text`, `#import/photo`
- [ ] T021 [US1] Подборки.
  - `RecipeScalerNative/Views/DiscoverRootView.swift`: при `.padRegular` заголовок и `DiscoverFeedSegmentPicker` (ширина 320) в одной строке вместо пикера под large title (~:29-31); лента `.iPadReadableWidth(720)`; ✦ (`IPadAssistantToolbarButton` из T018).
  - `RecipeScalerNative/Views/Discover/DiscoverPublicProfileView.swift`: `.iPadReadableWidth(1100)`, сетка `DiscoverRecipeCardGrid` как есть.

  — `#discover/feed`, `#discover/author`
- [ ] T022 [US1] Создать `RecipeScalerNativeUITests/Specs/IPadShellSpec.swift` (`XCTSkipUnless` iPad):
  - `testSidebarContents`, `testFooterPrivateShowsAccountId`, `testCollectionTapOpensRecipes`, `testNewCollectionFromSidebar`;
  - `testProfileHasNoShakeRow` — в листе;
  - `testFooterOpensProfileSheet`: «Моё всё» и «Готово», выбор сайдбара прежний, «Готово» закрывает; переключение «Публичный профиль» обновляет футер после закрытия;
  - `testTopBarProfileOpensSheet` (`-IPadSidebarHidden=1`), `testSidebarHasNoProfileTab`;
  - `testTopBarHasNoBadges` (`-IPadSidebarHidden=1`), `testCompactHasNoMoreTab` (окно ½ или `-DebugWindowWidth`), `testCollectionInTopBarShowsRecipesTab`.

  Прогнать на iPad; на iPhone — `AppShellNavigationSpec` и `verify-ui-smoke.sh`. — `#recipes/sidebar`, `#recipes/tabs`, `#profile/public`, `#profile/private`

**Checkpoint (US1)**:
- iPad iPadOS 26.2+: сайдбар, верхний бар, нижний бар в ½ и ⅓ — по layout.md §Карта состояний.
- Покупки и подборки по центру; профиль «Моё всё» — лист из футера и верхнего бара, выбор не меняется, в ½ и ⅓ — вкладка; импорт в form sheet; встряхивание не работает.
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
  - заголовок «Все рецепты» / название коллекции; при плейсменте `.topBar` (сайдбар скрыт; читается `@Environment(\.tabBarPlacement)`, S2) — меню выбора «Все рецепты | коллекции» с галочкой;
  - поиск и меню «+» как есть; состояние поиска (`searchText`) — снаружи `NavigationStack` колонки (во вью-модели списка или у родителя), чтобы переживать переход колонка ↔ выезд поверх (T024).

  Тот же режим для `RecipeScalerNative/Views/CollectionFolderView.swift`. — `#recipes/sidebar`, `#recipes/tabs`, `#recipes/search`
- [ ] T024 [US2] Создать `RecipeScalerNative/Views/IPad/IPadRecipesSplitView.swift` по варианту **B** (T006, plan.md Р5): `HStack` из двух `NavigationStack`, **без `NavigationSplitView`** (у него тулбары колонок уезжают под таб-бар после переключения сайдбара):
  - `listMode`: `.inline` / `.hidden` / `.overlay`;
  - `.inline` — колонка списка 320 (`NavigationStack { RecipeListView(columnMode: true) }`) + `Divider` 1 pt + панель `NavigationStack { YDocRecipeDetailView(recipeId:).id(recipeId) }`; фон и стиль колонки — вручную;
  - ширина контента измеряется через `onGeometryChange` (iOS 18+) / `GeometryReader` (iOS 17) и передаётся в `IPadLayoutPolicy`;
  - своя кнопка «Список рецептов» (`ToolbarItem(placement: .topBarLeading)`, `sidebar.left`), если список не `.inline`: при достаточной ширине → `.inline`, иначе → `.overlay`;
  - `.overlay` — `.overlay(alignment: .leading)`: затемнение 0.25 (тап → `.hidden`) + список 320 с фоном и тенью; выбор рецепта в `.overlay` → `.hidden`;
  - поиск — `.searchable` колонки списка (лупа в тулбаре колонки, S4), состояние снаружи стека (T023): запрос переживает `.inline` ↔ `.hidden` ↔ `.overlay`;
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

## Phase 5: User Story 3 — Ассистент панелью справа (P2)

**Goal**: своя панель ассистента 340 pt справа от `TabView` из любой вкладки (не `.inspector` — спайк S5), история поповером, лист в compact, один чат на панель и лист.  
**Independent Test**: spec.md US3.

- [ ] T032a [US3] Общая сессия ассистента (plan.md Р7). Сейчас `RecipeScalerNative/Views/AssistantSheet.swift` держит сессию в `@State` (~:26-56) и в `onDisappear` (~:185-210) отменяет задачи, поэтому панель и лист (разные экземпляры) теряют черновик и обрывают ответ (S5, `s5-03`–`s5-05`).
  - Создать `RecipeScalerNative/Services/AssistantSessionModel.swift`: `@MainActor @Observable final class` с `threadId`, `threads`, `messages`, `input`, `attachments`, `isSending`, `streamTask`, `bootstrapTask`, `externalSendTask` и методами, которые сейчас живут в view (отправка, бутстрап, смена треда, сброс).
  - Владелец — `RecipeScalerNative/App/AppContainer.swift`; передавать в `AssistantSheet(session:)` явно, не через `@Environment` (ловушка iOS 26).
  - Отмена задач — в модели: явное закрытие (`close()`), смена `coordinator.assistantSessionEpoch` (перенести `teardownForSessionInvalidation`), logout. `onDisappear` view задачи не отменяет; `threadId` по-прежнему пишется в `AssistantSessionStore`.
  - iPhone: лист работает как раньше; закрытие листа отменяет стрим и сохраняет тред. Черновик переживает закрытие и повторное открытие.
  - Создать `RecipeScalerNativeTests/AssistantSessionModelTests.swift`: `testDraftSurvivesViewSwap`, `testCloseCancelsStream`, `testEpochChangeDropsStaleStream`, `testLogoutResetsSession`.
  - Проверка: `bash scripts/verify-assistant.sh` на iPhone — зелёный; `bash scripts/test-fast.sh`.
  - Если перенос выходит за одну сессию или ломает iPhone-поведение — STOP и спросить (деградация «черновик теряется при панель ↔ лист» — только с согласия человека).

  — `#assistant/chat`, `#assistant/new` (на iPhone — лист без изменений)
- [ ] T032 [US3] Панель ассистента уровня оболочки в `RecipeScalerNative/Views/AppShellView.swift` (~:426), **не `.inspector`** (S5: `.inspector` на `TabView` обнуляет верхний safe area вкладок, STOP 2):
  - `HStack(spacing: 0) { tabView; if showAssistant && layoutMode == .padRegular { Divider().ignoresSafeArea(); AssistantSheet(session:, presentation: .inspector).frame(width: IPadLayoutMetrics.inspectorWidth).transition(.move(edge: .trailing)) } }` + `.animation(.snappy, value: showAssistant)`;
  - `AssistantSheetModifier` (~:1046-1072) получает `.constant(false)` при `.padRegular` и ту же `AssistantSessionModel` (T032a);
  - один `showAssistant` (~:106);
  - переход лист ↔ панель при смене size class без потери чата и черновика (общая модель T032a);
  - панель переживает смену вкладок.

  — `#assistant/chat`
- [ ] T033 [US3] `RecipeScalerNative/Views/AssistantSheet.swift`: режим `AssistantPresentation.inspector` (содержимое панели T032) — заголовок «Ассистент», группа (история, новый чат) и × (закрыть). История (~:129) открывается `.adaptivePopover` с содержимым `RecipeScalerNative/Views/AssistantThreadListSheet.swift`. В листе — как на iPhone. — `#assistant/history`, `#assistant/new`
- [ ] T034 [US3] Переключение.
  - ✦ на рецепте, «Покупках», «Подборках» и `.pinned`-иконка «Ассистент» верхнего бара открывают и закрывают панель без смены вкладки (`IPadShellItem`, T012).
  - ✦ на «Покупках» и «Подборках» открывает новый чат.
  - `IPadRecipesSplitView` учитывает панель в ширине контента (FR-022): ширина измеряется у раздела, панель уже вычтена.

  — `#assistant/chat`, `#assistant/new`
- [ ] T035 [US3] Создать `RecipeScalerNativeUITests/Specs/IPadAssistantSpec.swift`: `testInspectorOpensFromRecipe` (панель 340 pt), `testTabSwitchKeepsInspector`, `testTabSwitchKeepsDraft`, `testSizeClassSwitchKeepsChat` (черновик и сообщения после панель → лист → панель), `testHistoryPopover`; тулбары вкладок с открытой панелью не уходят под таб-бар. iPhone: `bash scripts/verify-assistant.sh`. Ручной проход `#assistant/*` в альбомной, книжной и окне ⅓. — `#assistant/chat`, `#assistant/history`, `#assistant/new`

**Checkpoint (US3)**: панель ассистента открывается из любой вкладки и переживает смену вкладок, список прячется, рецепт остаётся в две колонки в альбомной; в compact — лист с тем же чатом; iPhone — лист как раньше, 0 отличий.

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
- [ ] T038 [US4] Таймеры поповером по вердикту S6 (plan.md Р7).
  - Тап по капсуле `tabViewBottomAccessory` при `.padRegular` ставит флаг `timerPopoverShown` на уровне оболочки (`RecipeScalerNative/Views/AppShellView.swift` ~:650-664) вместо раскрытой панели. `.popover` **внутри** аксессуара не работает (S6) — не ставить.
  - Поповер 380 pt с `MobileTimerPanel(.insetExpanded)` прикреплён к невидимому якорю оболочки; фрейм аксессуара — через `onGeometryChange` → `.popover(attachmentAnchor: .rect(.rect(frame)), arrowEdge: .bottom)`, чтобы стрелка указывала на капсулу и при открытом сайдбаре; `.presentationCompactAdaptation(.sheet)`.
  - Аксессуар есть и в режиме сайдбара (S6) — своей капсулы не делать.
  - Перепроверить серией открытий и закрытий, что аксессуар не пропадает (в спайке пропал один раз).
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
  - `IPadRecipesSplitView` прячет список (`isEditing` в `IPadLayoutPolicy`), сайдбар сворачивается через `IPadSidebarControl` (`sidebar.isHidden = true`, S2) и возвращается после «Готово», если был открыт;
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

## Phase 9: User Story 7 — Многозадачность в одном окне (P3)

**Goal**: вся матрица ширин в одном окне с изменяемым размером (Split View, Slide Over, Stage Manager) без потерь состояния. Несколько окон вне scope (STOP 5, спайк S7).  
**Independent Test**: spec.md US7.

- [ ] T049 [US7] Матрица ширин.
  - Добавить в `scripts/verify-ipad-layout.sh` проход по layout.md §Матрица приёмки через `-DebugWindowWidth`.
  - Вручную проверить на симуляторе Split View (½, ⅔, ⅓), Slide Over и Stage Manager с непрерывным изменением размера одного окна: нет белых экранов и мигания, рецепт и коллекция сохраняются.
  - **Ландшафт** (не проверен спайком, plan.md §Непроверенное): повернуть Simulator.app через `osascript` (cmd+→ или меню Device › Rotate Right) и снять 1194 и 1366 с открытым и скрытым сайдбаром — встаёт ли сайдбар рядом с контентом. Если поворот не автоматизируется — отметить в задаче и передать владельцу проверку на устройстве (human gate).
  - Эмодзи в подписях коллекций сайдбара — на симуляторе с эмодзи-шрифтом или на устройстве.

  — все 24 состояния, `#recipes/sidebar` … `#menubar/view` (layout.md §Карта состояний), окна ⅔ / ½ / ⅓ (layout.md §Матрица приёмки)
- [ ] T050 [US7] Одно окно (S7 FAILED → STOP 5; решение записано в `docs/DECISIONS.md` 2026-10-12, Q4).
  - Проверить, что `UIApplicationSupportsMultipleScenes` в `RecipeScalerNative/Info.plist` нет и не появился; в меню «Окно» нет пункта нового окна, «Закрыть окно» без второго окна работает как системный.
  - Работы над несколькими окнами нет: перенос `AppShellCoordinator` на сцену, адресация `DeepLinkRouter`, разбор синглтонов — будущая спека.

  — `#menubar/file` («Закрыть окно» без второго окна), `.other-win` прототипа не делаем
- [ ] T051 [US7] Старый путь iPadOS 17.0–26.1 (spec.md Q1: на 17 API сайдбара нет, на 18–26.1 — общий гейт оболочки 26.2; расширение на 18+ — на потом).
  - Создать iPad-симулятор на iOS 18.4 (`xcrun simctl create … com.apple.CoreSimulator.SimRuntime.iOS-18-4`) и проверить iPad без сайдбара: системный таб-бар, колонки рецепта (вариант B), панель ассистента, поповеры, form sheet. Это не проверено спайком (plan.md §Непроверенное).
  - Капсулы таймеров нет.
  - iOS 17 — если runtime доступен, иначе отметить как непроверенное.

  — `#recipes/tabs`, `#assistant/chat`
- [ ] T052 [US7] Исправить найденные в T049–T051 переходы. Повторить матрицу. — строки `#recipes/tabs`, `#assistant/chat`, `#shopping/recipe` из layout.md §Матрица приёмки, упавшие в T049

**Checkpoint (US7)**: SC-005 — 100% проверок матрицы сохраняют рецепт и коллекцию; ландшафт проверен или передан владельцу; одно окно подтверждено.

---

## Phase 10: Polish

- [ ] T053 [P] Строки: все новые ключи en + ru в `RecipeScalerNative/Resources/Localizable.xcstrings`, телефонные ключи переиспользованы (FR-032); `bash scripts/lint-i18n.sh`, `RecipeScalerNativeTests/LocalizationConsistencyTests`. Проверить русский и английский интерфейс на iPad. — `#recipes/sidebar`, `#menubar/file`, `#menubar/recipe`, `#menubar/view`, `#profile/private`
- [ ] T054 [P] Документация:
  - `docs/DECISIONS.md` — оболочка iPad, старый путь (Q1, сайдбар на 18+ — на потом), перетаскиваемый разделитель и его ключ `UserDefaults` (Q5). Колонки (B), панель ассистента и одно окно уже записаны 2026-10-12 по итогам спайка — дополнить, если реализация от них отошла;
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
- [ ] T057 Независимое ревью отдельным агентом (не self-review) по plan.md: инварианты iPhone, ловушка environment в тулбарах, утечки стеков в `TabSection`, async lifecycle футера и `AssistantSessionModel`, изоляция UIKit-обхода в `IPadSidebarControl`. — все 24 состояния, `#recipes/sidebar` … `#menubar/view` (layout.md §Карта состояний)

**Checkpoint (Polish)**: `verify-all.sh` зелёный, ревью без блокирующих замечаний, human gates отмечены.

---

## Dependencies & Execution Order

- **Setup (T001–T004)** → **Foundational (T005–T011)** → истории.
- **T005, T006** — сделаны (2026-10-12). T007–T011 — сделаны.
- **US1 (T012–T022, T019a)** блокирует остальные истории.
  - Внутри: T012 → T013 → T014 (первый шаг — проверка динамической видимости `.pinned`-вкладок) → (T016, T017); `IPadSidebarControl` из T014 нужен T016 и T041; T015 → T016; T015 → T019 (оба трогают `AccountView` / `AccountAvatarView`); T018–T020 параллельно после T014; T021 после T018; T019a после T012, T014, T015, T016, T019 (все трогают `AppShellCoordinator` / оболочку / `AccountView`); T022 последней, после T019a.
- **US2 (T023–T031)** после US1.
  - T023 → T024 → T025 → T026; T027 параллельно с T025; T028 после T024; T029 после T023–T028. Разделитель T025 опирается на `detailLeftWidth` из T007.
- **US3, US4, US5** после US2, независимы друг от друга.
  - US5 использует колонки из T025.
  - US3: T032a → T032 → (T033, T034) → T035. T034 трогает `IPadRecipesSplitView` после T024.
- **US6** после US1–US5 (публикует их действия). **US7**: T049 и T051 — после US3 и US4 (матрица и старый путь проверяют инспектор, поповеры и капсулу таймеров); T050 — в любой момент (проверка, кода нет); T052 — после T049–T051.
- **Polish** последней.

## Phase summary

| Фаза | Задачи | Количество |
|------|--------|-----------|
| 1 Setup | T001–T004 | 4 |
| 2 Foundational | T005–T011 | 7 |
| 3 US1 Оболочка (P1) | T012–T022, T019a | 12 |
| 4 US2 Рецепты (P1) | T023–T031 | 9 |
| 5 US3 Ассистент (P2) | T032a, T032–T035 | 5 |
| 6 US4 Готовка и действия (P2) | T036–T040 | 5 |
| 7 US5 Правка (P2) | T041–T044 | 4 |
| 8 US6 Клавиатура и меню (P3) | T045–T048 | 4 |
| 9 US7 Многозадачность (P3) | T049–T052 | 4 |
| 10 Polish | T053–T057 | 5 |
| **Всего** | | **59** |
