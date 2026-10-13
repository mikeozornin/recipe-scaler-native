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
  - `testLeftColumnIsFixedAndKeepsTheSteps` (вместо `testLeftColumnClamp`, решение 2026-10-13): панели 873 и 1194 → 400; 720 → 399 (правой ≥ 320); 721 → 400; 719 → `nil`.

  — `#recipes/sidebar`, `#recipes/tabs`, `#assistant/chat`

  **2026-10-12 (T024, раскладка Notes):** `resolve(contentWidth:contentHeight:recipeExpanded:isEditing:)`, новая `listColumnWidth(contentWidth:contentHeight:)`, `showsExpandButton` вместо `showsListButton`; порог 560 + 321 заменён долями ½ / ⅓ и 320 + 1 + 320 (layout.md §Токены).
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

  **2026-10-12 (T024):** кнопки «Список рецептов» больше нет — идентификатор `ipad-recipe-expand-button` у «Развернуть» / «Свернуть»; `-IPadListHidden=1` запускает с развёрнутым рецептом.

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
- [x] T017 [US1] «Новая коллекция» в сайдбаре: `.sectionActions` → системный алерт с `TextField` → обрезка пробелов, пустое имя не сохраняется, single-flight `isSaving` → `syncService.createFolder(name:)`. Общий помощник вынести из `CollectionsRootView.commitNewFolder` (`RecipeScalerNative/Views/CollectionsRootView.swift` ~:458-484) и использовать в обоих местах. — `#recipes/sidebar`

  **Сделано и проверено:** общий помощник `RecipeScalerNative/Views/NewCollectionCommit.swift` (обрезка, пустое имя → `nil`, single-flight) — в `CollectionsRootView.commitNewFolder` и в сайдбаре. Строка «+ Новая коллекция» — в конце секции «Коллекции»; алерт «Новая коллекция» / «Название коллекции» / «Отмена» / «Создать», «Создать» неактивна для пустого имени и одних пробелов. На симуляторе создана и сразу удалена тестовая коллекция DEBUG-пользователя «iPad 081 test.»; она появилась в сайдбаре и в сетке. iPhone `--iphone-regression` `recipes-collection`, `recipes-list` — 0 отличий. Скриншот `tmp/ipad-verify/us1/t017-01-sidebar-new-collection.png`.
  **Отклонение:** `accessibilityIdentifier` не доходит ни до строки действия секции, ни до поля алерта (iPadOS 26.3) — идентификаторы не добавлены, UI-тест ищет по подписи.
- [x] T018 [P] [US1] Создать `RecipeScalerNative/Views/IPad/IPadAssistantToolbarButton.swift` (✦; в US1 открывает телефонный лист ассистента, новый чат). Покупки (`RecipeScalerNative/Views/ShoppingListView.swift`):
  - `.iPadReadableWidth(720)`;
  - «Купить во Вкусвилле» только иконкой (`AppToolbarStyle.iconOnly`), если ширина контента < 640 — только при `.padRegular`; в compact как на iPhone (`labeledIcon`, ~:704);
  - ✦ справа при `.padRegular`.

  — `#shopping/recipe`, `#shopping/az`

  **Сделано и проверено:** `IPadAssistantToolbarButton` (координатор передаётся явно) — справа в тулбаре покупок, в одной «капсуле» с «Купить во Вкусвилле» и «Поделиться»; тап открывает телефонный лист ассистента с пустым чатом. Список — колонка 720 по центру, фон `systemGroupedBackground` и по бокам. Проверено на iPad Pro 11: портрет (верхний бар и плавающий сайдбар), альбом (сайдбар рядом и верхний бар). iPhone `--iphone-regression` `shopping-az` — 0 отличий. В `verify-ipad-layout.sh` перед каждым запуском пишется нейтральный текст в буфер симулятора (Simulator копирует туда буфер Mac; ссылка показывает баннер импорта и ломает сравнение), буфер Mac не трогается. Скриншоты `tmp/ipad-verify/us1/t018-01-shopping-tabs.png`, `t018-02-shopping-sidebar.png`, `t018-04-landscape-shopping.png`, `t018-05-landscape-tabs.png`, `t018-06-assistant-sheet.png`.
  **Отклонение:** правило «< 640» не спасает: в верхнем баре (и под плавающим сайдбаром в портрете) подпись выталкивает тулбар в «…». Подпись только при сайдбаре рядом со страницей (`tabBarPlacement == .sidebar` и страница сдвинута, `minX > 0`) и ширине ≥ 640; иначе иконка. `ToolbarSpacer` между ✦ и остальными не поставлен — с ним ✦ уходит в «…».
- [x] T019 [P] [US1] Профиль и встряхивание.
  - `RecipeScalerNative/Views/AccountView.swift`: строка встряхивания (~:579-585) скрыта при `idiom == .pad` (в листе и во вкладке compact); строка «Аккаунт» — как на iPhone (`AccountAvatarView` из T015). Ограничение ширины не ставить: в `.padRegular` профиль — лист (T019a), в compact — телефонная страница.
  - `RecipeScalerNative/Utils/ShakeToOpenAssistantPreference.swift`: `isActive(idiom:)`; использовать в `AppShellView` (~:205, ~:214).
  - Тесты `testPhoneHonorsPreference`, `testPadIgnoresShake` в `RecipeScalerNativeTests/ShakeToOpenAssistantPreferenceTests.swift`.

  — `#profile/public`

  **Сделано и проверено:** `isActive(idiom:)` — iPad не реагирует на встряхивание, остальные устройства следуют настройке; используется в `handleDeviceShake` и `routePendingShakeAssistantOpenRequest`. Строка встряхивания в профиле скрыта при `idiom == .pad` (во вкладке compact `-DebugWindowWidth 400` её нет — `tmp/ipad-verify/us1/t019-01-profile-compact-no-shake.png`; лист — T019a). На iPhone строка на месте; `ShakeToOpenAssistantPreferenceTests` 7/7; iPhone `--iphone-regression` `profile-public`, `assistant-chat` — 0 отличий.
- [x] T019a [US1] Профиль «Моё всё» — form sheet в широком окне (spec.md Q7, FR-004a, FR-004b; plan.md Р2a; образец — Scrapp `RootView.swift:55`, `:113-137`, `:163-178`).
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

  **Сделано и проверено (iPad Pro 11", портрет):** иконка «Профиль» в верхнем баре и футер сайдбара открывают form sheet «Моё всё» с «Готово» справа; выбранный раздел не меняется («Рецепты», «Покупки»), плавающий сайдбар прячется перед листом; «Готово» и смахивание вниз закрывают лист. `-OpenTab=profile` (и с `-IPadSidebarHidden=1`) → лист поверх «Рецептов»; `-DebugWindowWidth=400` → вкладка «Профиль» нижнего бара, без «Готово» и без строки встряхивания. Урок Scrapp: отказ в привязке (`IPadShellSelection` не меняет выбор) пустой страницы «Профиля» не оставляет — под листом страница раздела, подсвечен прежний раздел; оставлен этот вариант, остальные входы (`requestRemindersSetup`, `-OpenTab`, расширение окна) нормализует `onChange`. `pendingRemindersSetup` лист обрабатывает при появлении: в `AccountView` это уже делает `.task` (`consumePendingRemindersSetupIfNeeded`), правка не нужна. Тесты: `IPadProfileSheetPolicyTests` 4/4, `AppShellCoordinatorTests` (+4), `IPadShellItemTests` (+1) — 36/36. В `verify-ipad-layout.sh` добавлены iPad-состояния `profile-tabs`, `recipes-compact`, `profile-compact` (`IPAD_VERIFY_COMPACT_WIDTH`, по умолчанию 400); `profile-public` на iPad — лист. iPhone `--iphone-regression` `profile-public`, `recipes-list` — 0 отличий. Скриншоты `tmp/ipad-verify/us1/t019a-02-topbar-profile-sheet.png`, `t019a-04-footer-sheet.png`, `tmp/ipad-verify/profile-public-portrait-full.png`, `profile-compact-portrait-full.png`.
  **Отклонение:** лист и обе нормализации — в новом `RecipeScalerNative/Views/IPad/IPadProfileSheetModifier.swift` (один модификатор на `IPadAdaptiveTabView` и на `legacyTabView`; на iPhone `legacyTabView` без него). `resolve` возвращает `.recipes` и тогда, когда `previous` — не раздел (`.profile`, `.assistant`, `.importTab`). Старый путь (iPadOS < 26.2) собран, но на симуляторе не проверен: iPad-симулятора с iOS 18.4 нет.
- [x] T020 [P] [US1] Импорт: на iPad-симуляторе проверить, как `RecipeScalerNative/Views/ImportRecipeSheet.swift` (detents `[.large]`, ~:216) показывается в широком окне. Если не form sheet около 560 × 720 — добавить `.iPadFormSheet()` при `.padRegular`. В compact — без изменений. — `#import/text`, `#import/photo`

  **Проверено (iPad Pro 11", портрет, верхний бар):** `-OpenTab=import` — лист импорта уже form sheet по центру, около 580 × 650 pt, с ручкой, фон затемнён; вкладки «Текст» и «Фото» — телефонные экраны как есть. Код не менялся: `.iPadFormSheet()` не нужен. Окно ½ на симуляторе не воспроизводится (`-DebugWindowWidth` сужает только корень, лист показывает окно), в compact код тот же, что на iPhone. Скриншоты `tmp/ipad-verify/us1/t020-01-import-before.png`, `t020-02-import-photo.png`.
- [x] T021 [US1] Подборки.
  - `RecipeScalerNative/Views/DiscoverRootView.swift`: при `.padRegular` заголовок и `DiscoverFeedSegmentPicker` (ширина 320) в одной строке вместо пикера под large title (~:29-31); лента `.iPadReadableWidth(720)`; ✦ (`IPadAssistantToolbarButton` из T018).
  - `RecipeScalerNative/Views/Discover/DiscoverPublicProfileView.swift`: `.iPadReadableWidth(1100)`, сетка `DiscoverRecipeCardGrid` как есть.

  — `#discover/feed`, `#discover/author`

  **Сделано и проверено (iPad Pro 11", портрет):** «Подборки» крупным заголовком слева и сегменты 320 справа в одной строке (как `.lt-row` прототипа), лента и «Моя лента» в колонке 720, ✦ справа открывает лист ассистента; со сдвинутым сайдбаром то же; страница автора — колонка 1100 (в портрете 834 на всю ширину), сетка без изменений; `-DebugWindowWidth=400` — телефонный вид (пикер под large title, без ✦). iPhone: `--iphone-regression --only discover-feed,discover-author,shopping-az` — 0 отличий. Скриншоты `tmp/ipad-verify/us1/t021-*.png`.

  **Отклонение:** заголовок бара на iPad убран через `toolbar(removing: .title)` (iOS 18+), чтобы «Подборки» не дублировались в баре; `navigationTitle` остаётся для кнопки «Назад». `DiscoverFeedSegmentPicker` получил параметр `horizontalPadding` (по умолчанию 16, как было). `iPadReadableWidth` на iPhone (по идиоме) теперь возвращает содержимое без рамок: даже `nil`-рамки сдвигали содержимое `ScrollView` автора на доли точки, и картинки отличались от базы (120 642 пикселя).
- [x] T022 [US1] Создать `RecipeScalerNativeUITests/Specs/IPadShellSpec.swift` (`XCTSkipUnless` iPad):
  - `testSidebarContents`, `testFooterPrivateShowsAccountId`, `testCollectionTapOpensRecipes`, `testNewCollectionFromSidebar`;
  - `testProfileHasNoShakeRow` — в листе;
  - `testFooterOpensProfileSheet`: «Моё всё» и «Готово», выбор сайдбара прежний, «Готово» закрывает; переключение «Публичный профиль» обновляет футер после закрытия;
  - `testTopBarProfileOpensSheet` (`-IPadSidebarHidden=1`), `testSidebarHasNoProfileTab`;
  - `testTopBarHasNoBadges` (`-IPadSidebarHidden=1`), `testCompactHasNoMoreTab` (окно ½ или `-DebugWindowWidth`), `testCollectionInTopBarShowsRecipesTab`.

  **Статус (исправлено):** первая отметка «сделано и проверено» была преждевременной — тесты не прогонялись, а проверка US1 на локальном бэкенде нашла дефекты. После исправлений `IPadShellSpec` — 11/11 на iPad Pro 11" (локальный бэкенд, свежий пользователь). Исправления:
  - пустой раздел «Коллекции» (у нового пользователя 0 коллекций) пропадал вместе с заголовком и «Новой коллекцией»: `TabSection` без вкладок система убирает. Теперь в пустом разделе одна дочерняя вкладка `.newCollection`, скрытая в сайдбаре (`.defaultVisibility(.hidden, for: .sidebar)`): она не видна и не выбирается, но держит заголовок и действие раздела (iPadOS 26.3). Id `ipad-sidebar-new-collection` / `ipad-new-collection-name-field` заданы, но система их выбрасывает — тесты ищут по id или по подписи;
  - `scrollAccount` листал `account_root`, а он совпадает с двумя элементами — теперь `collectionViews[account_root]`;
  - `SeedClient.addShoppingItems` / `addRecipeToShoppingList` вызывали несуществующие `/api/shopping-list/*` (404): у списка покупок нет REST-записи (Yjs-документ). `testTopBarHasNoBadges` добавляет пункт в приложении; REST-кейс US2 в `ShoppingListCompletionSpec` удалён;
  - `verify-ipad-layout.sh`: без `IPAD_VERIFY_DISCOVER_PROFILE` состояния `discover-*` пропускаются (не снимать чужой профиль по умолчанию); `recipes-sidebar` на iPad запускается с DEBUG `-IPadSidebarShown=1` — сайдбар виден и в портрете;
  - лист профиля, оставшийся после сужения окна, + тап «Профиль» в compact давали два `AccountView`: `IPadProfileSheetPolicy` при открытом листе оставляет лист и прежний раздел в любом режиме;
  - `NewCollectionCommit` обрезает `.whitespacesAndNewlines`: имя из одних переводов строк не сохраняется.

  **Сделано:** все 11 тестов в `IPadShellSpec` (портрет, iPadOS 26.2+; на iPhone и ниже 26.2 — `XCTSkip`). Для теста футера `SeedClient.setDisplayName` (`PATCH /api/users/name`), в `UIA` — `accountShakeOpenAssistantToggle`. Сборка `build-for-testing` на iPad и iPhone — без ошибок; на iPhone спека пропускается («iPad only»). Запросы спеки сверены одноразовым пробником только на чтение на DEBUG-аккаунте (в репозиторий не попал): верхние вкладки — кнопки с `isSelected`, строки сайдбара со счётчиком («Покупки, 11»), в верхней панели счётчиков нет, «Профиль»/«Ассистент» в сайдбаре отсутствуют, «Готово» листа найдено по id, строки встряхивания в листе нет, «Создать» выключено для пустого имени (алерт закрыт «Отменой», коллекция не создана), тап по коллекции закрывает оверлей, открывает «Вкусняшки» и оставляет выбранными «Рецепты», после открытия сайдбара строка выбрана; при `-DebugWindowWidth=400` — пять вкладок снизу без «Ещё», «Профиль» — вкладка без «Готово». Тестам нужен локальный бэкенд (`register-auto`); запуск против прода запрещён, без бэкенда все 11 пропускаются.

  **Отклонение:** у таргета UI-тестов `TARGETED_DEVICE_FAMILY` 1 → «1,2»: с одним iPhone раннер на iPad работал в режиме совместимости, `UIDevice.current.userInterfaceIdiom` был `.phone`, и `XCTSkipUnless` пропускал спеку и на iPad. На iPhone ничего не меняется (`AppShellNavigationSpec` собирается и запускается как раньше).

  Прогнать на iPad; на iPhone — `AppShellNavigationSpec` и `verify-ui-smoke.sh`. — `#recipes/sidebar`, `#recipes/tabs`, `#profile/public`, `#profile/private`

**Checkpoint (US1)**:
- iPad iPadOS 26.2+: сайдбар, верхний бар, нижний бар в ½ и ⅓ — по layout.md §Карта состояний.
- Покупки и подборки по центру; профиль «Моё всё» — лист из футера и верхнего бара, выбор не меняется, в ½ и ⅓ — вкладка; импорт в form sheet; встряхивание не работает.
- iPhone: 0 отличий скриншотов, smoke и `AppShellNavigationSpec` зелёные.
- Ручной проход человека по `#recipes/sidebar`, `#recipes/tabs`, `#shopping/*`, `#discover/*`, `#import/*`, `#profile/*`.
- Можно выпускать.

---

## Phase 4: User Story 2 — Рецепты: колонка списка и две колонки (P1)

**Goal**: колонка списка рядом с рецептом (½ контента в книжной, ⅓ в альбомной, не меньше 320 pt), рецепт в две колонки по ширине, «Развернуть» / «Свернуть» как в Apple Notes, контекстное меню.  
**Independent Test**: spec.md US2.

- [x] T023 [US2] Режим колонки в `RecipeScalerNative/Views/RecipeListView.swift` (только при `.padRegular`):
  - строка выбирает рецепт через `RecipesSelection` вместо `NavigationLink(value:)` (~:535), выбранная строка выделена;
  - плитка папок (`viewModeMenu`, ~:403-435) скрыта;
  - заголовок «Все рецепты» / название коллекции; при плейсменте `.topBar` (сайдбар скрыт; читается `@Environment(\.tabBarPlacement)`, S2) — меню выбора «Все рецепты | коллекции» с галочкой;
  - поиск и меню «+» как есть; состояние поиска (`searchText`) — снаружи `NavigationStack` колонки (у родителя, `IPadRecipesSplitView`), чтобы переживать «Развернуть» / «Свернуть» и телефонный стек (T024); смена коллекции запрос сбрасывает.

  Тот же режим для `RecipeScalerNative/Views/CollectionFolderView.swift`. — `#recipes/sidebar`, `#recipes/tabs`, `#recipes/search`

  **Отклонение:** поле поиска — под заголовком колонки (`.navigationBarDrawer`, как в прототипе `#recipes/search`), а не лупой в тулбаре колонки. Меню коллекций в заголовке включает оболочка флагом `showsCollectionMenu` (сайдбар скрыт; плейсмент сообщает выбранная страница через `reportsIPadSidebarShown`), сама колонка `tabBarPlacement` не читает. Заголовок не шире колонки минус 150 pt (`listTitleBarReserve`, layout.md): длинное имя коллекции обрезается «…», иначе бар уводил меню заголовка и кнопку справа в «Ещё» (941c0b5).
- [x] T024 [US2] Создать `RecipeScalerNative/Views/IPad/IPadRecipesSplitView.swift` по варианту **B** (T006, plan.md Р5): `HStack` из двух `NavigationStack`, **без `NavigationSplitView`** (у него тулбары колонок уезжают под таб-бар после переключения сайдбара). Раскладка — как в Apple Notes (решение владельца продукта 2026-10-12, `docs/DECISIONS.md`):
  - колонка списка (`NavigationStack` с `RecipeListView` / `CollectionFolderView` в режиме колонки, T023) + разделитель 1 pt + панель `NavigationStack { YDocRecipeDetailView(recipeId:).id(recipeId) }`;
  - ширина и высота контента измеряются `GeometryReader` и передаются в `IPadLayoutPolicy.resolve(contentWidth:contentHeight:recipeExpanded:isEditing:)`: список — `max(320, round((ширина − 1) × доля))`, доля ½ в книжной (высота контента больше ширины) и ⅓ в альбомной; с сайдбаром рядом правило работает на оставшейся ширине;
  - колонка видна всегда, когда рецепту рядом остаётся ≥ 320 pt; иначе раздел — телефонный стек (push);
  - «Развернуть» (`arrow.up.left.and.arrow.down.right`, `ToolbarItem(placement: .topBarLeading)` панели рецепта, id `ipad-recipe-expand-button`) — рецепт на весь раздел, колонка списка прячется, сайдбар, стоявший рядом с контентом, прячется через `IPadSidebarControl`; кнопка становится «Свернуть» (`arrow.down.right.and.arrow.up.left`) и возвращает список и сайдбар в прежнее состояние. Без открытого рецепта и в compact кнопки нет;
  - флаг `recipeDetailExpanded` — в `AppShellCoordinator`, только на сессию: переживает смену вкладок и поворот, не перезапуск;
  - поиск — состояние снаружи стека колонки (T023): запрос переживает «Развернуть» / «Свернуть»;
  - передавать `isSplitActive = true` в привязку `IPadShellItem` (T012), пока split показан.

  Подключить в корень вкладки «Рецепты» при `.padRegular`. — `#recipes/focus`, `#recipes/tabs`

  **Отклонение:** первая версия (81118c0: `listMode` `.inline` / `.hidden` / `.overlay`, своя кнопка «Список рецептов» `sidebar.left`, список 320 поверх рецепта с затемнением) заменена раскладкой Notes по решению владельца (434ea8f). Порог `minDetailWithList` 560 → 320, список — доля контента вместо 320. Развёрнутый рецепт не удаляет колонку списка, а уводит её за левый край (прозрачная, без нажатий, `accessibilityHidden`): без колонки iPadOS переносит бар рецепта в строку верхнего таб-бара и после «Свернуть» оставляет там, пункты уходят в «Ещё». Стек колонки при этом пуст (2026-10-12): ни строк, ни «+», ни поиска для XCUITest, VoiceOver и Full Keyboard Access (`IPadRecipesSpec.testExpandCollapse`). Сайдбар, плавающий над контентом (книжная), «Развернуть» закрывает, а «Свернуть» не возвращает. Push на симуляторе на весь экран не воспроизводится (самое узкое — книжная 834: 417 + 1 + 416), проверен только `IPadLayoutPolicyTests`. `-IPadListHidden=1` теперь значит «рецепт развёрнут при запуске», сайдбар он не прячет. Сайдбар, спрятанный «Развернуть», возвращается только им самим (2026-10-12, `AppShellCoordinator.setRecipeDetailExpanded`, `IPadLayoutPolicy`): сужение окна до push или compact сворачивает рецепт, выход из аккаунта сбрасывает и показывает сайдбар; если пользователь сам открыл сайдбар, флаг снимается и «Свернуть» его не трогает; свёрнутый не на «Рецептах» (пустая коллекция) сайдбар ждёт возврата на «Рецепты» в широком окне. Повторный тап по «Рецепты» оставляет открытый рецепт.
- [x] T025 [US2] Две колонки рецепта.
  - Создать `RecipeScalerNative/Views/YDocRecipeDetailColumns.swift`.
  - В `RecipeScalerNative/Views/YDocRecipeDetailView.swift` вынести левую колонку (фото, заголовок, порции, ингредиенты, КБЖУ, ~:280-396) и правую (`StepsSection` / `RecipeDescriptionEditorBlock`, ~:400-414) в `@ViewBuilder`.
  - Одна колонка — прежний `VStack` в прежнем порядке.
  - Две колонки (`.padRegular` и панель ≥ 720) — `HStack`: левый `ScrollView` шириной `IPadLayoutPolicy.detailLeftWidth` (T007), разделитель, правый `ScrollView` с шагами не шире 660 и отступами 32 (с 2026-10-13 — 16 и верх по левой колонке, решение владельца, DECISIONS).
  - `DetailScrollViewProbe` на правой колонке, `.mobileTimerPanelBottomPadding` на обеих, `AwakeScrollChromeModifier` на внешнем контейнере.
  - Между колонками статичная линия 1 pt (spec.md FR-012a, plan.md Р6); левая колонка `min(400, панель − 1 − 320)`, та же ширина в правке (T041).
  - **Пересмотрено владельцем 2026-10-13:** перетаскиваемый разделитель Q5 (область захвата 12 pt, упоры 320 / 480, `@AppStorage("ipad.recipeDetailLeftColumnWidth")`, VoiceOver «Ширина колонок» ±20 pt) удалён вместе с ручкой, строками и тестами. Строка «КБЖУ на» с выбором базы переносит выбор под заголовок, если не помещается в колонку (`ViewThatFits`, `RecipeNutritionHeaderLayoutTests`): раньше она вылезала, и вертикальный `ScrollView` сдвигал всю колонку влево.

  — `#recipes/tabs`, `#recipes/sidebar`

  **Отклонение:** правка пока в одну колонку (не шире 720 по центру) — две колонки в правке и общая ширина появятся в T041 (US5). На разделителе была небольшая «ручка», чтобы его было видно и за что тянуть (удалена с разделителем 2026-10-13).
- [x] T026 [US2] Варианты тулбара рецепта в `RecipeScalerNative/Views/YDocRecipeDetailView.swift` (~:825-880):
  - `.phone` — как сейчас;
  - `.padWide` (панель ≥ 600) — «…», «Поделиться», «Не гасить экран», ✦, «Изменить» с текстом;
  - `.padNarrow` — «…», «Не гасить экран», ✦, карандаш без текста;
  - слева — «Развернуть» / «Свернуть» (T024).

  ✦ — `IPadAssistantToolbarButton`. Зависимости передавать явно. — `#recipes/sidebar` (узкий), `#recipes/tabs` (широкий)

  **Отклонение:** ✦ и «Изменить» — отдельные капсулы через `ToolbarSpacer` (iOS 26). ✦ только при видимом сайдбаре (2822afe, FR-021): при таб-баре сверху там закреплена вкладка «Ассистент», второй вход не нужен. Третий стиль `.padBesideTabBar` (b6daa69) — одна капсула «…», «Не гасить экран», карандаш, когда бар рецепта делит строку плавающего таб-бара; после T024 (колонка списка всегда в иерархии) бар туда не переезжает, и на симуляторе этот стиль больше не встречается.
- [x] T027 [P] [US2] Контекстное меню строки в `RecipeScalerNative/Views/RecipeListView.swift` (только при `idiom == .pad`):
  - «Закрепить/Открепить», «В коллекцию», «В список покупок», «Поделиться», разделитель, «Удалить» — на тех же обработчиках, что свайпы (~:544-573);
  - «Поделиться» → `RecipeShareSheet` (вынести из `private` в `RecipeScalerNative/Views/RecipeDetailShareButton.swift`, если не хватает `isPublic` / `hasImage` / `hasSteps` у строки — пункт отложить и записать здесь, FR-017).

  — `#recipes/context`

  **Отклонение:** «Поделиться» отложен: строкам списка (`CollectionEntry`) не хватает `isPublic` и `hasSteps` для `RecipeShareSheet` (FR-017). У пунктов иконки, как в системных меню; новый ключ `ipad.recipe.context.add-to-collection` («В коллекцию»). Меню только в широком окне (`.padRegular`, 2026-10-12): узкое окно iPad — телефон, меню нет, как на iPhone.
- [x] T028 [US2] Правила выбора.
  - Ничего не выбрано → первый рецепт списка (закреплённые сверху).
  - Удалён открытый → следующий.
  - Удалена выбранная коллекция → «Все рецепты».
  - Диплинки (`AppShellCoordinator.handleDeepLink` ~:256, Spotlight, быстрые действия) открывают рецепт в панели и выделяют строку.
  - Логика — в `RecipeScalerNative/Routing/RecipesSelection.swift`, тесты — в `RecipesSelectionTests`.

  — `#recipes/collection`
- [x] T029 [US2] iPhone-регрессия после T023–T028: `bash scripts/verify-ipad-layout.sh --iphone-regression` (рецепт, правка, список, коллекция, поиск) — 0 отличий; `bash scripts/verify-description-editor.sh`, `bash scripts/verify-recipe-collections.sh` на iPhone — зелёные. Расхождения исправить в этой задаче. — `#recipes/sidebar`, `#recipes/collection`, `#recipes/search`, `#edit/edit` на iPhone

  **Итог 2026-10-12 (f940c4a):** 9 состояний, 0 отличий; `discover-feed` и `discover-author` скрипт пропускает без `IPAD_VERIFY_DISCOVER_PROFILE` (там чужие публичные данные). `verify-description-editor.sh` и `verify-recipe-collections.sh` на iPhone — VERIFIED. Код не менялся. Первые три прогона шли параллельно со сборками iPad и не прошли: отличались пиксели стеклянного таб-бара и полоски «домой» (`profile-public`, `shopping-az`, `import-text`), содержимое совпадало. Контрольный прогон на базовом коммите a3d592c дал 0 отличий в этих состояниях. Четвёртый прогон без параллельных сборок прошёл без повторов.
- [x] T030 [US2] Создать `RecipeScalerNativeUITests/Specs/IPadRecipesSpec.swift`: `testListAndTwoColumns`, `testCollectionSelection`, `testExpandCollapse` («Развернуть» прячет список и сайдбар, стоявший рядом, «Свернуть» возвращает оба; развёрнутый вид переживает смену вкладки), `testRotationKeepsRecipe`, `testContextMenu`, `testSearchFiltersColumn`; `testColumnDividerDragPersists` удалён вместе с разделителем 2026-10-13, `testListAndTwoColumns` проверяет левую колонку 400 ± 1. — `#recipes/tabs`, `#recipes/focus`, `#recipes/collection`, `#recipes/context`, `#recipes/search`

  **Отклонение:** каждый тест — свежий пользователь с двумя рецептами через REST, без ингредиентов (bulk-ингредиенты на локальном бэкенде отвечают 500); коллекцию тест создаёт в приложении через «В коллекцию» (`POST /api/collections` — 404). Отдельного теста на push нет: на симуляторе его не воспроизвести, правило покрыто `IPadLayoutPolicyTests`. Ширины проверяются по `frame`: список — ⅓ или ½ контента, рядом с сайдбаром — от окна минус 280 (колонка уходит под плавающий сайдбар); «нет списка» — колонка за левым краем (T024). Снимки XCTest в альбомной на симуляторе iPadOS 26 — обрезанный портретный буфер, поэтому снимки для ревью сняты `simctl io screenshot` (`tmp/ipad-verify/us2/redesign/`). Прогон: 7/7 на iPad Pro 11" (iPadOS 26.3), на iPhone спека пропускается.
- [ ] T031 [US2] Ручной проход по layout.md §Матрица приёмки для `recipes/*`: альбомная и книжная, весь экран и ⅔, сайдбар виден и скрыт; колонки рецепта на самой узкой ширине с двумя колонками (панель 720) — ничего не вылезает, в том числе с КБЖУ (разделитель колонок пальцем и трекпадом снят с проверки 2026-10-13: разделитель удалён). Отметить «пройдено / не пройдено» по каждому пункту. — `#recipes/*`

  **Подготовлено автоматически 2026-10-12, ручной проход не делался.** На симуляторе iPad Pro 11" пройдено: альбомная и книжная на весь экран, в альбомной — сайдбар скрыт и виден, «Развернуть» / «Свернуть» в каждом из этих состояний (снимки `tmp/ipad-verify/us2/redesign/`); разделитель колонок перетаскиванием XCUITest до упора и сохранение после перезапуска (`testColumnDividerDragPersists`, тест удалён с разделителем 2026-10-13). 2026-10-13: панель 720 (`-DebugWindowWidth`) в ru и en, с КБЖУ, секциями и длинными названиями, список и развёрнутый вид — ничего не вылезает (`tmp/ipad-verify/device-fixups/`). Не пройдено: книжная с плавающим сайдбаром над рецептом (снимка нет); окна ⅔ и ½ (Split View и Stage Manager на симуляторе не автоматизируются), а с ними push на экране; VoiceOver. Разделитель пальцем и трекпадом и сохранение ширины больше не проверяются: разделителя нет.

**Checkpoint (US2)**: колонки и две колонки рецепта совпадают с прототипом по матрице; открытый рецепт переживает поворот и смену ширины; iPhone — 0 отличий. Можно выпускать.

---

## Phase 5: User Story 3 — Ассистент панелью справа (P2)

**Goal**: своя панель ассистента 340 pt справа от `TabView` из любой вкладки (не `.inspector` — спайк S5), история поповером, лист в compact, один чат на панель и лист.  
**Independent Test**: spec.md US3.

- [x] T032a [US3] Общая сессия ассистента (plan.md Р7). Сейчас `RecipeScalerNative/Views/AssistantSheet.swift` держит сессию в `@State` (~:26-56) и в `onDisappear` (~:185-210) отменяет задачи, поэтому панель и лист (разные экземпляры) теряют черновик и обрывают ответ (S5, `s5-03`–`s5-05`).
  - Создать `RecipeScalerNative/Services/AssistantSessionModel.swift`: `@MainActor @Observable final class` с `threadId`, `threads`, `messages`, `input`, `attachments`, `isSending`, `streamTask`, `bootstrapTask`, `externalSendTask` и методами, которые сейчас живут в view (отправка, бутстрап, смена треда, сброс).
  - Владелец — `RecipeScalerNative/App/AppContainer.swift`; передавать в `AssistantSheet(session:)` явно, не через `@Environment` (ловушка iOS 26).
  - Отмена задач — в модели: явное закрытие (`close()`), смена `coordinator.assistantSessionEpoch` (перенести `teardownForSessionInvalidation`), logout. `onDisappear` view задачи не отменяет; `threadId` по-прежнему пишется в `AssistantSessionStore`.
  - iPhone: лист работает как раньше; закрытие листа отменяет стрим и сохраняет тред. Черновик переживает закрытие и повторное открытие.
  - Создать `RecipeScalerNativeTests/AssistantSessionModelTests.swift`: `testDraftSurvivesViewSwap`, `testCloseCancelsStream`, `testEpochChangeDropsStaleStream`, `testLogoutResetsSession`.
  - Проверка: `bash scripts/verify-assistant.sh` на iPhone — зелёный; `bash scripts/test-fast.sh`.
  - Если перенос выходит за одну сессию или ломает iPhone-поведение — STOP и спросить (деградация «черновик теряется при панель ↔ лист» — только с согласия человека).

  — `#assistant/chat`, `#assistant/new` (на iPhone — лист без изменений)

  **Сделано и проверено (abbae09):** `AssistantSessionModel` держит тред, сообщения, черновик, вложения и задачи стрима, бутстрапа и внешней отправки; владелец — `AppContainer`, в `AssistantSheet(session:)` передаётся явно. Жизненный цикл ведёт оболочка: `beginPresentation` при открытии, `close()`, когда `showAssistant` становится `false`, `resetForLogout` из корня; смена эпохи сбрасывает устаревший стрим; `onDisappear` задачи не отменяет. Смена view (панель ↔ лист) только переподключает view: чат, черновик и идущий ответ сохраняются. На iPhone всё как раньше, кроме одного: черновик переживает закрытие и повторное открытие листа (plan.md Р7). `AssistantSessionModelTests` — 10 тестов: четыре из задачи и ещё шесть (идущий ответ и внешний запрос при смене view, черновик после закрытия, «Новый чат» чистит черновик, повторное открытие возвращает недавний тред, новый чат его не подхватывает). `test-fast` зелёный; `verify-assistant.sh` на iPhone — VERIFIED (`tmp/ipad-verify/us3/verify-assistant-iphone-t032a.png`, в конце US3 — `verify-assistant-iphone-final.png`). STOP не понадобился.
- [x] T032 [US3] Панель ассистента уровня оболочки в `RecipeScalerNative/Views/AppShellView.swift` (~:426), **не `.inspector`** (S5: `.inspector` на `TabView` обнуляет верхний safe area вкладок, STOP 2):
  - `HStack(spacing: 0) { tabView; if showAssistant && layoutMode == .padRegular { Divider().ignoresSafeArea(); AssistantSheet(session:, presentation: .inspector).frame(width: IPadLayoutMetrics.inspectorWidth).transition(.move(edge: .trailing)) } }` + `.animation(.snappy, value: showAssistant)`;
  - `AssistantSheetModifier` (~:1046-1072) получает `.constant(false)` при `.padRegular` и ту же `AssistantSessionModel` (T032a);
  - один `showAssistant` (~:106);
  - переход лист ↔ панель при смене size class без потери чата и черновика (общая модель T032a);
  - панель переживает смену вкладок.

  — `#assistant/chat`

  **Сделано и проверено (2299119, 6d896ee):** панель 340 pt в `HStack` рядом с `TabView`, разделитель на всю высоту, выезд справа; один `showAssistant` на панель и лист. Смена size class меняет панель на лист и обратно над той же сессией (T032a); панель переживает смену вкладок (`IPadAssistantSpec`). Закрытие ассистента сбрасывает внешний запрос: устаревший запрос больше не мешает следующему открытию вкладки (PI-5).

  **Отклонение:** у листа своя привязка, не `.constant(false)`. `get` — `showAssistant && layoutMode != .padRegular`. `set` игнорирует закрытие, когда лист уступает место панели (`@State`-зеркало `assistantShowsAsPanel`). Иначе при переходе compact → regular SwiftUI закрывал лист через замыкание, которое ещё видело compact, ставил `showAssistant = false`, и панель не появлялась (6d896ee).
- [x] T033 [US3] `RecipeScalerNative/Views/AssistantSheet.swift`: режим `AssistantPresentation.inspector` (содержимое панели T032) — заголовок «Ассистент», группа (история, новый чат) и × (закрыть). История (~:129) открывается `.adaptivePopover` с содержимым `RecipeScalerNative/Views/AssistantThreadListSheet.swift`. В листе — как на iPhone. — `#assistant/history`, `#assistant/new`

  **Сделано и проверено (06d12e2, 62e5e29):** бар панели — «Ассистент» слева, справа группа [история, новый чат], `ToolbarSpacer` и ×. История — `.adaptivePopover` 316 × 420 с содержимым `AssistantThreadListSheet` поверх чата; в листе история и бар как на iPhone. Снимки `tmp/ipad-verify/us3/panel-recipes-landscape.png`, `history-popover-landscape.png` (и копии `-900`).

  **Отклонение:** системный заголовок (`.inlineLarge`) делил строку бара с тремя кнопками и обрезался до «Асси…». Поэтому заголовок — ведущий элемент бара: шрифт display 20 pt, как `.insp-bar h3` в прототипе, ширина 120 pt (новый токен `inspectorTitleWidth`, layout.md §Токены). Если шире, × уходит в системное меню «Ещё». У панели нет своего accessibility id: его перекрывает `root_content`. Тесты находят панель по бару с × (`ipadAssistantInspectorCloseButton`); константа `ipadAssistantInspector` удалена из `AccessibilityIdentifiers` и `Selectors`.
- [x] T034 [US3] Переключение.
  - ✦ на рецепте, «Покупках», «Подборках» и `.pinned`-иконка «Ассистент» верхнего бара открывают и закрывают панель без смены вкладки (`IPadShellItem`, T012).
  - ✦ на «Покупках» и «Подборках» открывает новый чат.
  - `IPadRecipesSplitView` учитывает панель в ширине контента: ширина измеряется у раздела, панель уже вычтена.
  - На «Рецептах» открытая панель всегда прячет колонку списка (рецепт + чат), закрытие возвращает её (FR-022, решение владельца 2026-10-12).

  — `#assistant/chat`, `#assistant/new`

  **Сделано и проверено (fbcea26):**
  - Закреплённая вкладка «Ассистент» и ✦ открывают и закрывают панель, выбранная вкладка не меняется (FR-021).
  - ✦ на «Покупках» и «Подборках» открывает панель с новым чатом, набранный черновик сохраняется. Вкладка и ✦ рецепта, как и раньше, возвращают чат, открытый в последние 60 с.
  - На «Рецептах» с открытой панелью колонки списка нет, в альбомной рецепт в две колонки (контент 869 на iPad Pro 11" M4 с окном 1210; по §Матрица — 853). Закрытие возвращает список, открытый рецепт и выделенную строку.
  - Сплит или стек решается по ширине без панели (`IPadLayoutPolicy`, `assistantPanelOpen`; см. «Доработки после ревью US3» ниже), поэтому открытие и закрытие панели не меняет view рецепта (прокрутка, готовка) и не сворачивает развёрнутый рецепт. «Развернуть» скрыт, пока панель открыта; после закрытия состояние «развёрнут» возвращается.
  - PI-5: тап по вкладке в том же обновлении, что внешний запрос («Купить во Вкусвилле»), панель не закрывает. Внешний запрос в уже открытый ассистент уходит в сессию напрямую, без повторов (по id запроса).
  - Тесты: `IPadLayoutPolicyTests`, `AppShellCoordinatorTests`, `AssistantSessionModelTests`, `IPadAssistantSpec`.
  - Снимки `tmp/ipad-verify/us3/panel-recipes-landscape.png`, `panel-recipes-portrait.png`, `panel-shopping-landscape.png`, `shopping-sidebar-star-landscape.png` → `panel-shopping-from-star-landscape.png`.

  **Отклонение:**
  - В альбомной на весь экран iPadOS сам сворачивает сайдбар в верхний таб-бар, когда `TabView` сужается рядом с панелью (11″: 1210 → 869), и возвращает сайдбар после закрытия. ✦ в тулбаре при этом пропадает: вход и выход — закреплённая вкладка «Ассистент» (FR-021). Поведение системное, не наше. Строка «Альбомная · весь · да · да» §Матрица на 11″ поэтому не возникает; 13″ проверяет T049.
  - Пока панель открыта, управление без рук и «не гасить экран по прокрутке» на рецепте не взводятся: оболочка ставит `assistantRecipeContext.isAssistantSheetOpen = showAssistant`, а для листа на iPhone это правильно. Рядом с панелью рецепт виден, и решать это нужно в T036 (US4).
  - Пункта «панель + развёрнутый рецепт» нет: рядом с панелью список скрыт в любом случае, «Развернуть» не показывается.
- [x] T035 [US3] Создать `RecipeScalerNativeUITests/Specs/IPadAssistantSpec.swift`: `testInspectorOpensFromRecipe` (панель 340 pt), `testTabSwitchKeepsInspector`, `testTabSwitchKeepsDraft`, `testSizeClassSwitchKeepsChat` (черновик и сообщения после панель → лист → панель), `testHistoryPopover`; тулбары вкладок с открытой панелью не уходят под таб-бар. iPhone: `bash scripts/verify-assistant.sh`. Ручной проход `#assistant/*` в альбомной, книжной и окне ⅓. — `#assistant/chat`, `#assistant/history`, `#assistant/new`

  **Сделано и проверено 2026-10-13 (a7a9298, 62e5e29):**
  - `IPadAssistantSpec` — 6/6 на iPad Pro 11" (iPadOS 26.3); на iPhone спека пропускается. Каждый тест — свежий пользователь с одним рецептом через REST.
  - `testInspectorOpensFromRecipe`: панель 340 ± 2 у правого края, колонки списка нет (FR-022), рецепт не заходит под панель, «Развернуть» нет. × и вкладка «Ассистент» закрывают панель, выбор вкладки не меняется.
  - `testTabSwitchKeepsInspector`: панель и чат переживают «Рецепты» → «Покупки» → «Подборки» → «Рецепты». «Поделиться» на «Покупках» не уходит под таб-бар и под панель.
  - `testTabSwitchKeepsDraft`: черновик переживает смену вкладки, а также закрытие и повторное открытие панели.
  - `testSizeClassSwitchKeepsChat`: панель → лист → панель, те же сообщения и черновик.
  - `testHistoryPopover`: поповер поверх панели, панель остаётся.
  - `IPadRecipesSpec` 7/7 и `IPadShellSpec` 13/13 после US3.
  - iPhone: `verify-assistant.sh` — VERIFIED; `verify-ipad-layout.sh --iphone-regression` — 9 состояний, 0 отличий. `assistant-chat` один раз дал 1 пиксель и прошёл на штатном повторе скрипта.
  - Ручной проход (симулятор, снимки `tmp/ipad-verify/us3/`): альбомная (панель на «Рецептах» и «Покупках», поповер истории, сворачивание сайдбара), книжная (панель на «Рецептах»), compact ½ (лист с тем же чатом и черновиком, `compact-sheet-portrait.png`).

  **Отклонение:**
  - Добавлен `testToolbarButtonTogglesPanel`: ✦ на «Покупках» при сайдбаре открывает панель; сайдбар сворачивается в верхний бар (T034), и закрывает панель закреплённая вкладка.
  - Смена size class в тесте — новый DEBUG-аргумент `-DebugCompactInPortrait=1`: в книжной корень сужается до ½ окна (402, compact), в альбомной остаётся regular, поворот меняет size class на лету. Лист при этом показывает настоящее полноширинное окно, поэтому он выглядит как page sheet по центру, а не как лист в окне ½. Это артефакт хука.
  - В `RecipeScalerNativeUITests/Helpers/Selectors.swift` поправлен комментарий и удалена константа `ipadAssistantInspector` (id, добавленный в T033 и перекрытый `root_content`). `SeedClient` и `BaseTestCase` не менялись.
  - Окно ⅓ не проверено: Split View и Stage Manager на симуляторе не автоматизируются, а `-DebugWindowWidth=320` сужает только корень SwiftUI, лист показывает полное окно. Ручной проход ⅓ на устройстве — за человеком (T049).

  **Доработки после ревью US3 (2026-10-13, 9adb9e2…96c306f):**
  - Выход и смена аккаунта закрывают ассистента и сбрасывают его контекст рецепта. Одна точка — `AppContainer.resetAssistantForLogout()`: сессия и `AssistantRecipeContext` (`isAssistantSheetOpen`, `visibleRecipeId`). Её зовут `stopForLogout()` и `resetForAccountSwitch()`. Смена `assistantSessionEpoch` закрывает лист или панель. `onDismiss` листа пропускает только передачу чата в панель, поэтому лист, снесённый вместе с оболочкой на iPhone, тоже считается закрытым. Тесты — `AppContainerTests`.
  - Teardown сессии делает то же, что `resetForLogout()`: отменяет первый bootstrap и обновление истории, сбрасывает отложенный shake. Тест — `testTeardownDropsBootstrapShakeAndHistoryRefresh`.
  - `testCloseCancelsStream` и `testEpochChangeDropsStaleStream` доставляют буферизованные события до close/teardown. Они проверяют, что `messages`, `isSending` и `threadId` не тронуты; без guard в цикле стрима оба падают.
  - Новые тесты: повторный id запроса при открытом ассистенте уходит один раз; внешний запрос во время bootstrap уходит один раз после него.
  - В `IPadAssistantSpec` всегда истинная проверка заменена подсчётом полей ввода чата. Лист поверх панели она ловит: при мутации биндинга листа падает в двух тестах.
  - Пока панель открыта, сплит или стек на «Рецептах» решается по ширине без панели, есть рецепт или нет (`assistantPanelOpen`). Без рецепта (пустая коллекция) список остаётся рядом с панелью, выбор рецепта только прячет список. «Развернуть» скрыт всё время, пока панель открыта. Тест — `IPadLayoutPolicyTests.testAssistantPanelKeepsOneModeWithOrWithoutARecipe`, решение — в `docs/DECISIONS.md`.
  - Снимки книжной на 11″: `tmp/ipad-verify/us3-fixups/portrait-panel-empty-collection.png` (список 320 + пустая деталь 172 + панель 340) → `portrait-panel-recipe-open.png` (список скрыт, рецепт 493).
  - Проверки:
    - `test-fast` (1071, 0 падений), `policy-check`, `lint-i18n`;
    - Debug build-for-testing для iPad и iPhone, Release;
    - `IPadAssistantSpec` 6/6, `IPadRecipesSpec` 7/7, `IPadShellSpec` 13/13;
    - iPhone: `verify-assistant.sh` — VERIFIED. Базовая линия переснята с merge-base 3df9bdd, `--iphone-regression` — 9 состояний, 0 отличий.
  - M2 и L1 ревью остаются в T036 (US4).

**Checkpoint (US3)**: панель ассистента открывается из любой вкладки и переживает смену вкладок, список прячется, рецепт остаётся в две колонки в альбомной; в compact — лист с тем же чатом; iPhone — лист как раньше, 0 отличий.

---

## Phase 6: User Story 4 — Готовка и действия (P2)

**Goal**: полоса готовки на обе колонки, «Коллекции» поповером, таймеры поповером.  
**Independent Test**: spec.md US4.

- [x] T036 [P] [US4] Полоса готовки и управление без рук в двух колонках.
  - `ScreenAwakeStatusBanner` стоит под тулбаром на всю ширину панели (проверить `RecipeScalerNative/Views/AwakeScrollChromeModifier.swift` с раскладкой T025).
  - Команды прокрутки двигают правую колонку (`DetailScrollViewProbe`).
  - Прогнать `RecipeScalerNativeTests/AwakeScrollControllerTests` и `AwakeScrollEngineTests`.

  — `#recipes/cooking`

  **Сделано и проверено (commits): 5bc871c, ea7be79.**
  - Полоса уже стоит на всю ширину панели: `AwakeScrollChromeModifier` ставит её `safeAreaInset(.top)` над `YDocRecipeDetailColumns`. В альбомной без сайдбара у `screen_awake_banner` x 404, ширина 806, то есть полоса идёт над фото и над шагами. Код для этого не понадобился.
  - Команды прокрутки двигают правую колонку: `detailScrollProbe` стоит в её `ScrollView`. Тест `DetailScrollViewProbeTests.test_probe_in_two_columns_binds_the_right_column` (ea7be79).
  - M2 и L1 ревью US3 (5bc871c). `AssistantRecipeContext` различает «ассистент открыт» (`isAssistantOpen`) и «ассистент закрывает рецепт» (`coversRecipe`, только телефонный лист).
    - Рядом с панелью полоса готовки и управление без рук работают так же, как без панели.
    - Если с открытой панелью перейти на «Покупки» или «Подборки», оболочка отпускает скрытый рецепт (`releaseRecipe(hiddenBy:)`). Чип «Борщ» пропадает из композера, экран снова может гаснуть.
    - Выход из аккаунта сбрасывает все флаги.
    - На iPhone `coversRecipe` всегда равен `isAssistantOpen`.
    - Тесты: `AssistantRecipeContextTests` (10), `AppContainerTests`.
  - `AwakeScrollControllerTests` и `AwakeScrollEngineTests` прошли на iPad и в `test-fast` на iPhone.
  - Снимки `tmp/ipad-verify/us4/`:
    - `recipes-cooking-landscape.png`;
    - `recipes-cooking-landscape-assistant.png` — полоса при открытой панели;
    - `recipes-cooking-assistant-then-shopping.png` — на «Покупках» чипа рецепта нет;
    - `recipes-cooking-portrait.png`, `recipes-cooking-half.png`.

  **Отклонение:** временное решение T034 (флаг `isAssistantSheetOpen`, который ставили и для панели) заменено, запись в `docs/DECISIONS.md` помечена как устаревшая. Hands-free голосом и диктовка ассистента при открытой панели могут делить микрофон. Это проверяет владелец на устройстве (T040).
- [x] T037 [P] [US4] «Коллекции» поповером: `RecipeScalerNative/Views/RecipeDetailActionsMenu.swift` (~:61-62) — `.adaptivePopover` вместо `.sheet` при `.padRegular`; `RecipeScalerNative/Views/CollectionAssignSheet.swift` — ширина 300 в поповере, сохранение при закрытии как сейчас (~:112-114). Добавить `testCollectionsPopoverPersists` в `IPadRecipesSpec`. — `#recipes/collections`

  **Сделано и проверено (commits): d300a45, 6d7b9d8.**
  - В `.padRegular` пункт «…» → «Коллекции» открывает `CollectionAssignSheet` в поповере 300 × 420 через `adaptivePopover` и `iPadPopoverFrame`. На iPhone и в compact-окне iPad — телефонный лист.
  - Режим раскладки передаётся в меню тулбара явно: элементы бара могут получить запасное окружение.
  - Членство сохраняется при закрытии, как раньше.
  - `IPadRecipesSpec.testCollectionsPopoverPersists`:
    - поповер шириной 300;
    - новая коллекция отмечена сразу при создании;
    - тап мимо закрывает поповер и сохраняет членство;
    - в коллекции только этот рецепт;
    - при повторном открытии отметка на месте.
  - Снимки `tmp/ipad-verify/us4/recipes-collections-landscape.png`, `-portrait.png`, `-half.png` (в ½ — лист).

  **Отклонение:**
  - Высота 420 — новый токен `collectionsPopoverHeight`. В layout.md была только ширина, а у `List` своей высоты нет. 420 — как у поповера истории.
  - В iPadOS 26 поповер от кнопки бара вырастает из «…» и закрывает её. Поведение системное, принято.
- [x] T038 [US4] Таймеры поповером по вердикту S6 (plan.md Р7).
  - Тап по капсуле `tabViewBottomAccessory` при `.padRegular` ставит флаг `timerPopoverShown` на уровне оболочки (`RecipeScalerNative/Views/AppShellView.swift` ~:650-664) вместо раскрытой панели. `.popover` **внутри** аксессуара не работает (S6) — не ставить.
  - Поповер 380 pt с `MobileTimerPanel(.insetExpanded)` прикреплён к невидимому якорю оболочки; фрейм аксессуара — через `onGeometryChange` → `.popover(attachmentAnchor: .rect(.rect(frame)), arrowEdge: .bottom)`, чтобы стрелка указывала на капсулу и при открытом сайдбаре; `.presentationCompactAdaptation(.sheet)`.
  - Аксессуар есть и в режиме сайдбара (S6) — своей капсулы не делать.
  - Перепроверить серией открытий и закрытий, что аксессуар не пропадает (в спайке пропал один раз).
  - Содержимое панели не меняется («Сбросить все» не добавляем).

  — `#recipes/timers`

  **Сделано и проверено (commits): 1c123ea, 7223aa7.**
  - iPadOS 26.2+, `.padRegular`: тап по капсуле открывает поповер (`timerPopoverShown` оболочки).
  - Поповер 380 pt. Внутри — телефонная `MobileTimerPanel(.insetExpanded)` без изменений.
  - Поповер привязан к невидимому якорю 1 × 1 в углу `TabView`, `attachmentAnchor` — фрейм капсулы. Стрелка указывает вниз на капсулу и при сайдбаре, пока поповер открыт, он следует за капсулой.
  - Как поповер закрывается:
    - тап мимо (в том числе по капсуле: она под областью закрытия поповера) или шеврон панели;
    - переход в compact-окно;
    - пропала капсула (таймеры кончились).
  - При переходе в широкое окно раскрытая панель сворачивается.
  - На iPhone и в compact-окне iPad панель раскрывается, как раньше.
  - DEBUG `-MobileTimerPanelExpanded=1` в широком окне открывает поповер.
  - `IPadRecipesSpec.testTimersPopoverClosesOnATapOutsideOrTheChevronAndKeepsTheCapsule`, два запущенных таймера, четыре круга открытия и закрытия:
    - поповер 380, над капсулой и по её центру;
    - строки таймеров есть только в поповере;
    - после каждого закрытия капсула на месте и нажимается;
    - с сайдбаром поповер следует за сдвинутой капсулой.
  - Снимки `tmp/ipad-verify/us4/recipes-timers-landscape.png`, `-landscape-capsule.png`, `-landscape-sidebar.png`, `-portrait.png`, `-half.png`.

  **Отклонение:**
  - Фреймы капсулы и якоря хранятся в ненаблюдаемом классе `TimerPopoverGeometry` в `@State`, измерения в точке {0, 0} отбрасываются. Причина: аксессуар пересобирается при каждом обновлении оболочки и первый раз измеряется вне окна. Запись фрейма в `@State` зацикливала оболочку и вешала приложение.
  - Якорь — точка 1 × 1, а не view размером с `TabView`. Хост поповера во весь размер перекрывал нажатия по контенту.
- [x] T039 [US4] Проверить таблицу готовки (`RecipeScalerNative/Views/Cooking/ProcessTableCookingPresenter.swift`, ветки по idiom ~:55-120; `ProcessTableCookingOrientationGate.swift`) на iPad в обеих ориентациях и в окне ½. Исправлять, только если на iPad есть принудительный поворот или обрезка. — `#recipes/cooking`

  **Сделано и проверено (commits): 0c36438.**
  - Принудительного поворота на iPad нет:
    - `cookingOrientations` — `.all`;
    - `requestLandscape` и `unlockOrientation` работают только на iPhone;
    - гейт ориентации принимает книжную.
  - Обрезка была в окнах уже 420 pt (⅓, Slide Over): view мерил свою стартовую матрицу 420 pt, а не окно. Исправлено: у корневого фрейма `ProcessTableCookingView` добавлен `minWidth: 0`. На iPhone таблица работает только в альбомной (от 667 pt), там ничего не меняется.
  - Тест `ProcessTableCookingLayoutTests.testCookingOnIPadFollowsTheWindowInEveryOrientation` идёт только на iPad.
    - Маска ориентаций `.all`.
    - Окна 1210 × 834, 834 × 1210, 597, 400 и 320 pt: матрица на всю ширину и не обрезана, «Закрыть» в окне, ориентация сцены не меняется.
    - Снимки `tmp/ipad-verify/us4/t039-ipad-cooking-{landscape,portrait,half,narrow,third}.png`.

  **Отклонение:** вход в таблицу готовки на экране рецепта закомментирован (TODO 074), из UI до неё не дойти. Поэтому проверка — юнит-тестом на симуляторе iPad, а не проходом по экрану.
- [x] T040 [US4] Ручной проход `#recipes/cooking`, `#recipes/collections`, `#recipes/timers` в альбомной (две колонки), книжной и ½. `bash scripts/verify-timer-widget.sh` на iPhone — зелёный. — `#recipes/cooking`, `#recipes/collections`, `#recipes/timers`

  **Сделано и проверено (автоматическая часть, 2026-10-13):**
  - Проход на симуляторе iPad Pro 11" M4 (iPadOS 26.3). Свежий пользователь, рецепты выдуманы. Снимки в `tmp/ipad-verify/us4/`, у каждого есть копия `-900`.
    - `#recipes/cooking`: альбомная в две колонки, с панелью ассистента, после перехода на «Покупки», книжная, ½.
    - `#recipes/collections`: альбомная и книжная — поповер, ½ — лист.
    - `#recipes/timers`: альбомная (поповер; капсула; поповер при сайдбаре), книжная — поповер, ½ — раскрытая панель.
  - Окно ½ сделано через DEBUG `-DebugWindowWidth=597`. Лист в нём центрируется по всему экрану — артефакт хука, как в T035.
  - Проверки:
    - iPhone: `verify-timer-widget.sh` — все проверки прошли; `verify-assistant.sh` — VERIFIED; `verify-ipad-layout.sh --iphone-regression` отдельно — 9 состояний, 0 отличий.
    - `test-fast` — 1083 теста, 0 падений, 2 пропущены (тесты только для iPad); `policy-check` и `lint-i18n` прошли.
    - Debug build-for-testing для iPad и iPhone и Release собираются.
    - На iPad, по одной спеке: `IPadRecipesSpec` 9/9, `IPadShellSpec` 13/13, `IPadAssistantSpec` 6/6.

  **Отклонение:** ручной проход на устройстве остаётся за владельцем:
  - управление без рук и «Не гасить экран» при открытой панели ассистента; не мешают ли друг другу голосовые команды без рук и диктовка ассистента (общий микрофон);
  - поповер таймеров при настоящем изменении окна (Stage Manager, Split View) и при повороте с открытым поповером;
  - таблица готовки при повороте и в узких окнах, когда 074 вернёт вход в неё;
  - поповер «Коллекции», закрывающий «…» (системное поведение iPadOS 26).

  **Доработки по ревью US4 (2026-10-13, DECISIONS «US4/US5 review fixes»):**
  - Поповер таймеров: ветка «повторный тап по капсуле закрывает» была недостижима, капсула только открывает поповер. DEBUG-запрос `-MobileTimerPanelExpanded` сбрасывается при показе и при любом закрытии (ff9a72d). Тест переименован (89218b5).
  - `DetailScrollViewProbeTests` собирает боевые `YDocRecipeDetailColumns`, проба стоит в правой колонке внутри них (3777e12).

**Checkpoint (US4)**: полоса готовки на обе колонки, поповеры «Коллекции» и таймеров в широком окне, листы в compact; iPhone без изменений.

---

## Phase 7: User Story 5 — Правка в две колонки (P2)

**Goal**: правка на всю ширину раздела, «Готово» над шагами, панель форматирования под шагами.  
**Independent Test**: spec.md US5.

- [x] T041 [US5] Вход в правку при `.padRegular`:
  - `IPadRecipesSplitView` прячет список (`isEditing` в `IPadLayoutPolicy`), сайдбар сворачивается через `IPadSidebarControl` (`sidebar.isHidden = true`, S2) и возвращается после «Готово», если был открыт;
  - правка раскладывается колонками T025 (та же линия и ширина левой колонки): слева шапка правки, порции, `YDocIngredientsEditSection`, справа `RecipeDescriptionEditorBlock`.

  — `#edit/edit`

  **Сделано и проверено (commits): 8f5841f; отступы колонки шагов как у левой — b254b82 (решение владельца 2026-10-13).**
  - Вход в правку при `.padRegular` разворачивает рецепт, как «Развернуть» (`IPadLayoutPolicy.expandsRecipeForEdit`). Условие: список и рецепт помещаются рядом.
    - Список уходит.
    - Сайдбар рядом с контентом сворачивается, и это запоминается.
  - Правка в колонках T025, с той же линией и шириной левой колонки:
    - слева шапка правки, порции и ингредиенты;
    - справа `RecipeDescriptionEditorBlock`.
  - `IPadRecipesSpec.testEditTwoColumns` проверяет:
    - альбомную и книжную (834 pt, regular): две колонки, списка нет, рецепт от левого края;
    - правку из открытого сайдбара: сайдбар прячется.

  **Отклонение:**
  - Сайдбар возвращается не по «Готово», а по «Свернуть». По T043 и `#recipes/focus` после «Готово» рецепт остаётся развёрнутым (DECISIONS 2026-10-13).
  - В push-стеке (окно, где списку нет места) и в compact правка раздел не меняет: там список и так не стоит рядом.
- [x] T042 [US5] Расположение элементов правки в две колонки.
  - Над правой колонкой только «Готово», как на iPhone (spec.md Q2; на iPhone — тулбар как сейчас, `YDocRecipeDetailView.swift` ~:850).
  - `formattingBarInset` (~:505-507, ~:776-789) через `.safeAreaInset(edge: .bottom)` правого `ScrollView`.
  - Проверить аппаратную и плавающую клавиатуру: курсор не уходит под клавиатуру, панель видна.

  — `#edit/edit`

  **Сделано и проверено (commits): 8f5841f, d92166b.**
  - На панели правки только «Готово». Кнопки «Развернуть»/«Свернуть» и ✦ в правке нет.
  - Панель форматирования — это `.safeAreaInset(edge: .bottom)` правого `ScrollView` (`YDocRecipeDetailColumns.rightBar`).
    - Она по ширине колонки шагов и стоит над клавиатурой.
    - Последняя строка шагов остаётся над панелью.
  - Число колонок решает ширина панели, ориентацию — высота без клавиатуры (`contentHeightIgnoringKeyboard`). Поэтому клавиатура ни то ни другое не меняет.
  - `testEditTwoColumns` в альбомной и книжной проверяет: кнопки панели над клавиатурой, панель в пределах колонки шагов.

  **Отклонение:** аппаратную и плавающую клавиатуру на симуляторе через XCTest не проверить, это ручная проверка (T044).
- [x] T043 [US5] После «Готово» рецепт открыт развёрнутым, список скрыт, «Свернуть» его возвращает (как `#recipes/focus`). Смена size class во время правки сохраняет фокус и текст. Одна колонка правки при панели < 720 — не шире 720 по центру. — `#edit/edit` → `#recipes/focus`

  **Сделано и проверено (commits): 8f5841f, ed1c5ef, d92166b.**
  - После «Готово» рецепт остаётся развёрнутым, список скрыт. «Свернуть» возвращает список и сайдбар, который спрятала правка.
  - При смене size class или переходе split ↔ push-стек view рецепта пересоздаётся. Правка живёт в `AppShellCoordinator.recipeEdit` (`IPadRecipeEditSession`) и переносит:
    - черновики порций и цвета;
    - набранный заголовок;
    - фокус: заголовок или курсор в шагах. Мост теперь шлёт `from`/`to`, а команда `focusAt` ставит курсор обратно.
  - Новый view подхватывает правку. Если в перестройке поднялось несколько view, правка остаётся за тем, что на экране.
  - Возврат в широкое окно посреди правки снова разворачивает рецепт.
  - Phone-стек iPad держит открытый рецепт после смены size class (`IPadStackPathKeeper`, отдельный fix). Раньше SwiftUI выталкивал путь, пока окно перестраивалось, и compact показывал список вместо рецепта.
  - При панели < 720 правка идёт одной колонкой, не шире 720, по центру (`RecipeDetailSingleColumnWidth`).
  - Тесты:
    - `IPadRecipesSpec.testEditSurvivesSizeClassChange` (`-DebugCompactInPortrait=1`): regular → compact → regular, сначала с фокусом в заголовке, потом в шагах. Текст и фокус сохраняются; после «Готово» рецепт развёрнут, заголовок и шаги сохранены.
    - `AppShellCoordinatorTests` (сессия правки, сайдбар, «Готово» в compact) и `IPadLayoutPolicyTests`.

  **Отклонение:**
  - Фокус в поле ингредиента не переносится; текст ингредиентов уже в Y.Doc.
  - Окно ⅔ в альбомной правится в две колонки (панель 776 pt, по layout.md), а Independent Test в spec.md ждёт одну.
  - Взаимодействие с ассистентом и поповерами — в DECISIONS 2026-10-13. Владелец принял поведение как есть (2026-10-13): ✦ в верхнем баре или сайдбаре доступен и в правке, в тулбаре правки только «Готово»:
    - ✦ в тулбаре правки нет; вход — закреплённая вкладка «Ассистент» (✦ в верхнем баре или сайдбаре).
    - Если сайдбар открыть посреди правки, входа в ассистента на экране нет до «Готово»: сайдбар не показывает закреплённую вкладку, а ✦ в тулбаре правки нет. Владелец подтвердил это 2026-10-13.
    - Таймеры скрыты, как на iPhone.
    - «Коллекции» недоступны, потому что нет «…».
- [x] T044 [US5] Тест `testEditTwoColumns` в `RecipeScalerNativeUITests/Specs/IPadRecipesSpec.swift`; `bash scripts/verify-description-editor.sh` на iPhone; ручной проход `#edit/edit` в альбомной, ⅔ и ½. — `#edit/edit`

  **Сделано и проверено (автоматическая часть, commits: 3500cc5):**
  - `testEditTwoColumns` и `testEditSurvivesSizeClassChange` в `IPadRecipesSpec`.
  - Проход на симуляторе iPad Pro 11" M4 (iPadOS 26.3), свежий пользователь, рецепты выдуманы. Снимки в `tmp/ipad-verify/us5/`, у каждого есть копия `-900`:
    - альбомная;
    - правка из открытого сайдбара;
    - ⅔ (`-DebugWindowWidth=776`, ширина ⅔ из layout.md);
    - ½ (`-DebugWindowWidth=597`, compact, как iPhone);
    - клавиатура с панелью форматирования;
    - после «Готово» (развёрнут);
    - правка с панелью ассистента;
    - отступы колонки шагов в книжной, чтение и правка, до и после b254b82: `padding-{reading,edit}-portrait[-before].png`.
  - Проверки, 2026-10-13, на коде 3500cc5:
    - `test-fast`: 1096 тестов, 0 падений, 2 пропущены. `policy-check` и `lint-i18n` проходят.
    - Сборки Debug build-for-testing для iPad и iPhone и Release собираются.
    - `IPadRecipesSpec` 11/11, `IPadShellSpec` 13/13, `IPadAssistantSpec` 6/6, каждая спека отдельно, на локальном бэкенде.
    - На iPhone `verify-description-editor.sh` — VERIFIED (зазор текст → панель 23,3 pt).
    - `verify-ipad-layout.sh --iphone-regression` отдельно — 9 состояний, 0 отличий. `assistant-chat` один раз дал 2 пикселя и прошёл на штатном повторе.

  **Отклонение:** ручной проход на устройстве остаётся за владельцем:
  - аппаратная клавиатура и плавающая клавиатура: курсор не уходит под клавиатуру, панель видна;
  - изменение окна посреди правки через Stage Manager и Split View (настоящий resize, а не DEBUG-хук);
  - первое касание шагов после клавиатуры заголовка. Под XCTest оно не ставило фокус в редактор, так было и на iPhone до US5. Вероятная причина — заглушённый `focus` у ещё не готового редактора; она исправлена в d92166b (DECISIONS 2026-10-13). Помощник теста по-прежнему касается второй раз, если панели нет, так что проверить пальцем.

  **Доработки по ревью US5 (2026-10-13, DECISIONS «US4/US5 review fixes»):**
  - Правка, оставленная на другой вкладке, заканчивается, когда её рецепт уходит из пути (a0532b9). Сброс пути при перестройке стека после смены раскладки правку не заканчивает: решает `IPadStackPathKeeper` (6112af2).
  - Заголовок не забирает фокус после смены одной и двух колонок посреди правки (068bfb7). UI-теста нет: нужен настоящий resize в Stage Manager.
  - `IPadStackPathKeeper` возвращает путь только после сигнала о перестройке стека, в течение 0,5 с, один раз и к живому рецепту; свои сбросы пути приложения его отменяют (0d54a2c).
  - Контекст ассистента очищает только тот view рецепта, который его поставил (baf5f61).
  - Мелочи: метрики колонки шагов меряют шрифты один раз (cf6af4b), `focusAt` берёт только целые конечные позиции (ad9e09f), view после «Готово» не подхватывает правку снова (fa61a1f). Два `onChange(of: descriptionChrome.isFocused)` старше 081, остаются (backlog «Вне 081»).
  - `testEditTwoColumns` требует открытого окна Simulator.app на iPad: без него после `typeText` редактор шагов получает только панель быстрых команд клавиатуры, и тест падает на «No software keyboard» на любом коммите, вплоть до базы US5. Сообщение теста и `docs/AGENT-WORKFLOW.md` теперь об этом говорят (cf60d16).
  - Проверки (cf60d16):
    - policy-check и lint-i18n проходят; build-for-testing на iPad и iPhone и Release собираются;
    - unit-тесты iPad 102/102 (6112af2); test-fast: 1108 прошли, 2 пропущены, 0 падений, самый долгий кейс 10 с;
    - `IPadRecipesSpec` 11/11, `IPadShellSpec` 13/13, `IPadAssistantSpec` 6/6, каждый отдельно, с открытым окном Simulator.app;
    - `verify-description-editor.sh`, `verify-timer-widget.sh` и `verify-assistant.sh` на iPhone проходят;
    - `verify-ipad-layout.sh --iphone-regression`: 9 состояний, 0 отличий. `edit-edit` прошёл со второй попытки: на первой был баннер приложения «Импортировать сайт из буфера обмена?».

**Checkpoint (US5)**: правка в две колонки совпадает с прототипом; на iPhone правка без изменений (0 отличий скриншотов).

---

## Phase 8: User Story 6 — Клавиатура и меню-бар (P3)

**Goal**: команды из layout.md §Меню в меню-баре и по шорткатам.  
**Independent Test**: spec.md US6.

- [x] T045 [US6] Создать `RecipeScalerNative/Views/IPad/IPadCommands.swift`: `FocusedValueKey` для `AppCommandActions` (вкладки, ассистент, новый рецепт, импорт, новая коллекция, поиск, сайдбар) и `RecipeCommandActions` (правка, порции, покупки, закрепить, коллекции, не гасить экран, удалить, поделиться). Публиковать через `.focusedSceneValue` из `AppShellView` и `YDocRecipeDetailView` **только при `idiom == .pad`**. — `#menubar/file`, `#menubar/recipe`, `#menubar/view`

  **Сделано и проверено (commits): ef9aedd, a30ced5, 14613a2.**
  - `IPadCommands.swift`: `AppCommandActions` и `RecipeCommandActions`, `FocusedValues`. `AppShellView` и `YDocRecipeDetailView` публикуют их через `focusedSceneValue` только на iPad; на iPhone значения нет, и шорткатов нет.
  - Действие `nil` — пункт серый. В правке у рецепта остаётся только «Готово», ⌘N и ⌘F тоже `nil`.
  - Оба значения `Equatable` без замыканий: равны при тех же пунктах и флагах, а замыкания читают рецепт и порции в момент вызова. Без этого каждое тело давало «новое» значение, SwiftUI гнал его через фокус сцены на каждом layout, и поворот iPad в компактное окно посреди правки вешал приложение (100% CPU). Исправлено в 14613a2.
  - Тесты: `AppShellCoordinatorTests` (⌘1–⌘4 не сбрасывают стеки, ⌘4 в широком окне — лист «Моё всё», запрос ⌘F берётся один раз за 1,5 с, ⇧⌘N закрывает лист профиля, значения команд сравнивают пункты, а не замыкания).

  **Отклонение:** в `AppCommandActions` нет действия сайдбара: ⌃⌘S — системный пункт (T046).
- [x] T046 [US6] `.commands` на `WindowGroup` в `RecipeScalerNative/RecipeScalerNativeApp.swift` (~:176):
  - «Файл» (`CommandGroup(after: .newItem)`), «Рецепт» (`CommandMenu`), «Вид» (`CommandGroup(before: .sidebar)` / `.toolbar`);
  - шорткаты по таблице layout.md §Меню;
  - в меню только действия, которые есть на iPhone: «Экспорт в PDF…» прототипа не добавляется (spec.md Q3);
  - строки — ключи `ipad.menu.*` в `RecipeScalerNative/Resources/Localizable.xcstrings`.

  — `#menubar/file`, `#menubar/recipe`, `#menubar/view`

  **Сделано и проверено (commits): ef9aedd.**
  - «Файл», «Рецепт», «Вид» по таблице layout.md §Меню, только на iPad. «Экспорт в PDF…» нет.
  - 8 ключей `ipad.menu.*` на русском и английском, `lint-i18n` проходит.
  - Системное меню «Найти» убрано (`findingPreference = .removed`), иначе оно забирает ⌘F.
  - Удержание клавиши не повторяет команду (`buttonRepeatBehavior(.disabled)`).

  **Отклонение:**
  - «Файл» заменяет системную группу (`CommandGroup(replacing: .newItem)`, а не `after:`): у приложения одно окно, пункта «Новое окно» нет.
  - ⌃⌘S — системный пункт «Показать боковую панель», а не своя команда через `IPadSidebarControl`: второй пункт с ⌃⌘S роняет приложение при запуске.
  - ⌘+ срабатывает и на ⌘= (UIKit), отдельного пункта ⌘= нет; другие раскладки — ручная проверка.
- [x] T047 [US6] ⌘↩ на «Готово» правки и ⌘F → `.searchFocused` колонки списка (iOS 18+; на 17 пункта нет). Проверить, что на iPhone с клавиатурой ничего нового не срабатывает. — `#edit/edit`, `#recipes/search`

  **Сделано и проверено (commits): ef9aedd, a30ced5.**
  - ⌘↩ висит на пункте меню «Готово», а не на кнопке: у шортката один владелец, и он виден при удержании ⌘.
  - ⌘F: вкладка «Рецепты» и фокус в поиск списка на экране (`.searchFocused`, iOS 18+; на 17 пункта нет). В широком окне рецепт сворачивается и панель, скрывающая список, закрывается; phone-стек возвращается к списку.
  - iPhone: `PhoneKeyboardSpec` жмёт ⌘=, ⌘E, ⇧⌘P, ⌘3, ⌘J, ⌘N на открытом рецепте — ничего не меняется; ⌘A в поиске доказывает, что клавиши доходят.
- [x] T048 [US6] Создать `RecipeScalerNativeUITests/Specs/IPadKeyboardSpec.swift` (`XCUIElement.typeKey`): ⌘E, ⌘↩, ⌘+, ⌘−, ⌘0, ⇧⌘L, ⇧⌘P, ⌃⌘A, ⌘⌫ (появляется подтверждение удаления, тест его отменяет), ⌘1–⌘4, ⌘J, ⌘F, ⌘N, ⇧⌘I, ⇧⌘N; меню «Рецепт» неактивно без рецепта. — `#menubar/recipe`

  **Сделано и проверено (commits): a30ced5, b2d84a9.**
  - `IPadKeyboardSpec`, 6 тестов: все шорткаты из списка; «Рецепт» неактивен без рецепта и в правке.
  - `typeKey` на iPadOS 26.3 теряет первую клавишу после запуска (тесты сначала жмут свободный ⌘K) и не доставляет ⌘↩ и ⌘⌫. `testHostKeys` просит `scripts/verify-ipad-keyboard.sh` прислать их HID-событиями (AXe): ⌘↩ из заголовка и из шагов, ⌘⌫ на рецепте (подтверждение, тест его отменяет), без рецепта и в поле поиска.
  - Самопроверка скрипта `scripts/tests/test-verify-ipad-keyboard.sh` в `policy-check`.
  - Прогон (14613a2): `bash scripts/verify-ipad-keyboard.sh` → VERIFIED (6 тестов, 6 клавиш хоста отправлены и увидены), iPad Pro 11" M4, iPadOS 26.3.

  **Отклонение:**
  - ⌘+ жмётся как ⌘= (`typeKey("+")` добавляет ⇧).
  - Меню-бара нет в дереве доступности: его вид и подсказки при удержании ⌘ — ручная проверка.
  - Ингредиент для ⇧⌘L набирается в правке рецепта из ⌘N: рецепт из REST в старом формате, его нельзя править, а ингредиенты по REST для него локальный бэкенд не принимает.

  **Проверки (14613a2):**
  - policy-check и lint-i18n проходят; build-for-testing на iPad и iPhone и Release собираются.
  - `AppShellCoordinatorTests` на iPad 58/58; test-fast на iPhone: 1113 прошли, 2 пропущены, 0 падений, ни один кейс не дольше 30 с.
  - `IPadRecipesSpec` 11/11, `IPadShellSpec` 13/13, `IPadAssistantSpec` 6/6, каждый отдельно, с открытым окном Simulator.app. До 14613a2 `testEditSurvivesSizeClassChange`, `testSizeClassSwitchKeepsChat` и `testCompactHasNoMoreTab` падали: приложение висело после поворота в компактное окно (см. T045).
  - `verify-ipad-keyboard.sh` → VERIFIED; `PhoneKeyboardSpec` на iPhone проходит.
  - `verify-description-editor.sh` на iPhone проходит; `verify-ipad-layout.sh --iphone-regression`: 9 состояний, 0 отличий. `profile-public` прошёл со второй попытки скрипта: на первой отличались 3 пикселя.

**Checkpoint (US6)**: все шорткаты срабатывают на iPad-симуляторе с аппаратной клавиатурой (SC-006); на iPhone поведение прежнее.

Проход владельца на устройстве: 2026-10-13 владелец запустил сборку 5724a1a (US6) на настоящем iPad Air 11" M3 — «на реальном ipad всё ок». Какие пункты он прошёл, не записано; ручные гейты (T004, T031, окно ⅓) этим не закрыты.

---

## Phase 9: User Story 7 — Многозадачность в одном окне (P3)

**Goal**: вся матрица ширин в одном окне с изменяемым размером (Split View, Slide Over, Stage Manager) без потерь состояния. Несколько окон вне scope (STOP 5, спайк S7).  
**Independent Test**: spec.md US7.

- [ ] T049 [US7] Матрица ширин.
  - Добавить в `scripts/verify-ipad-layout.sh` проход по layout.md §Матрица приёмки через `-DebugWindowWidth`.
  - Вручную проверить на симуляторе Split View (½, ⅔, ⅓), Slide Over и Stage Manager с непрерывным изменением размера одного окна: нет белых экранов и мигания, рецепт и коллекция сохраняются.
  - **Ландшафт** (не проверен спайком, plan.md §Непроверенное): повернуть Simulator.app через `osascript` (cmd+→ или меню Device › Rotate Right) и снять 1194 и 1366 с открытым и скрытым сайдбаром — встаёт ли сайдбар рядом с контентом. Если поворот не автоматизируется — отметить в задаче и передать владельцу проверку на устройстве (human gate).
  - Эмодзи в подписях коллекций сайдбара — на симуляторе с эмодзи-шрифтом или на устройстве. С 2026-10-12 строка как в телефонном списке: эмодзи — иконкой (картинка 28×24), без эмодзи — папка цветом коллекции, в заголовке только имя. Симулятор iOS 26.3 под macOS 15 эмодзи не рисует нигде (и в телефонной сетке коллекций — «?»), так что сам глиф — только на устройстве.

  — все 24 состояния, `#recipes/sidebar` … `#menubar/view` (layout.md §Карта состояний), окна ⅔ / ½ / ⅓ (layout.md §Матрица приёмки)

  **Частично (commits 19d4452, 23f6ce5); не закрыто: диск.**
  - Матрица автоматизирована: `IPadMultitaskingSpec` меняет ширину корня на лету (`-DebugWindowWidthLive=1`) и на каждой ширине проверяет панель (вкладки / нижний бар), колонку списка, колонки рецепта, панель ассистента, открытый рецепт и коллекцию (SC-005). `bash scripts/verify-ipad-layout.sh --matrix` снимает скриншоты хостом и пишет `matrix.txt`. Ландшафт тест поворачивает сам.
  - 11″ (iPad Pro 11" M4, iPadOS 26.3, сборка с исправлением T052): `testRecipesWidthsLandscape`, `…Portrait`, `…LandscapeWithSidebar`, `testAssistantWidthsLandscape` прошли; `testShoppingWidthsLandscape` упал на замере (`shopping_list` — весь экран), замер исправлен на ширину строки ввода, повторный прогон не сделан. Скриншоты — `tmp/ipad-verify/us7/ipad-pro-11-inch-m4-16gb/`, по ним раскладка верна, ✦ один, рецепт и коллекция на месте.
  - 13″ (1366) не прогнан.
  - Подмена ширины не двигает лист и сайдбар: листы показываются от полного окна, а сайдбар на ширинах меньше полной iPadOS сворачивает в верхний таб-бар. Владельцу на устройстве: Split View (½, ⅔, ⅓), Slide Over, Stage Manager с непрерывным изменением размера, сайдбар в ⅔, ½ на 13″ (678, regular), эмодзи в сайдбаре.
- [ ] T050 [US7] Одно окно (S7 FAILED → STOP 5; решение записано в `docs/DECISIONS.md` 2026-10-12, Q4).
  - Проверить, что `UIApplicationSupportsMultipleScenes` в `RecipeScalerNative/Info.plist` нет и не появился; в меню «Окно» нет пункта нового окна, «Закрыть окно» без второго окна работает как системный.
  - Работы над несколькими окнами нет: перенос `AppShellCoordinator` на сцену, адресация `DeepLinkRouter`, разбор синглтонов — будущая спека.

  — `#menubar/file` («Закрыть окно» без второго окна), `.other-win` прототипа не делаем

  **Проверено статически (5724a1a):** в `Info.plist` нет `UIApplicationSceneManifest` и `UIApplicationSupportsMultipleScenes`; один `WindowGroup` (`RecipeScalerNativeApp.swift`), нет `openWindow` и `requestSceneSessionActivation`; `IPadCommands.swift` заменяет `.newItem`, так что пункта «Новое окно» нет. Меню-бара нет в дереве доступности: вид меню «Окно» и «Закрыть окно» — проверка владельца на устройстве.
- [ ] T051 [US7] Старый путь iPadOS 17.0–26.1 (spec.md Q1: на 17 API сайдбара нет, на 18–26.1 — общий гейт оболочки 26.2; расширение на 18+ — на потом).
  - Создать iPad-симулятор на iOS 18.4 (`xcrun simctl create … com.apple.CoreSimulator.SimRuntime.iOS-18-4`) и проверить iPad без сайдбара: системный таб-бар, колонки рецепта (вариант B), панель ассистента, поповеры, form sheet. Это не проверено спайком (plan.md §Непроверенное).
  - Капсулы таймеров нет.
  - iOS 17 — если runtime доступен, иначе отметить как непроверенное.

  — `#recipes/tabs`, `#assistant/chat`

  **Заблокировано симулятором; передано владельцу.**
  - `IPadMultitaskingSpec` на iPad ниже 26.2 проходит старую оболочку: системный таб-бар и проверка, что сайдбара нет.
  - На симуляторе iOS 18.4 приложение падает при запуске: dyld не находит `/usr/lib/swift/libswiftWebKit.dylib`. Приложение ссылается на него через Swift-оверлей `WKWebView.callAsyncJavaScript(…) async` (deployment target 17); в рантаймах симулятора 18.4/18.5 библиотека лежит в `System/Cryptexes/OS/usr/lib/swift`, где dyld её не ищет. Известный баг рантайма (WebKit 293831); на устройствах, по отчётам, работает.
  - Runtime iOS 17 не установлен: непроверено.
  - Владельцу на iPad с iPadOS 17 или 18: запуск, таб-бар, колонки рецепта, панель ассистента, поповеры, form sheet, нет капсулы таймеров.
- [ ] T052 [US7] Исправить найденные в T049–T051 переходы. Повторить матрицу. — строки `#recipes/tabs`, `#assistant/chat`, `#shopping/recipe` из layout.md §Матрица приёмки, упавшие в T049

  **Исправлено (commit 23f6ce5); повтор матрицы не закончен.**
  - Окно ⅔ в альбомной (776 × 834 на 11″) считалось альбомным: высота мерилась внутри safe area, под барами. Теперь до краёв окна, и список занимает ½: 787 → 393, 720 → 360 (было 320). `IPadLayoutPolicyTests.testTwoThirdsLandscapeWindowSplitsInHalf`.
  - Повторный прогон на 11″ с исправлением подтвердил строки рецептов и ассистента; полный повтор (покупки, 13″) и итоговые гейты не прогнаны: на диске осталось меньше 1 ГБ.

**Checkpoint (US7)**: SC-005 — 100% проверок матрицы сохраняют рецепт и коллекцию; ландшафт проверен или передан владельцу; одно окно подтверждено.

---

## Phase 10: Polish

- [ ] T053 [P] Строки: все новые ключи en + ru в `RecipeScalerNative/Resources/Localizable.xcstrings`, телефонные ключи переиспользованы (FR-032); `bash scripts/lint-i18n.sh`, `RecipeScalerNativeTests/LocalizationConsistencyTests`. Проверить русский и английский интерфейс на iPad. — `#recipes/sidebar`, `#menubar/file`, `#menubar/recipe`, `#menubar/view`, `#profile/private`
- [ ] T054 [P] Документация:
  - `docs/DECISIONS.md` — оболочка iPad, старый путь (Q1, сайдбар на 18+ — на потом), колонки рецепта без перетаскиваемого разделителя (решение 2026-10-13, записано). Колонки (B), панель ассистента и одно окно уже записаны 2026-10-12 по итогам спайка — дополнить, если реализация от них отошла;
  - `docs/AGENT-WORKFLOW.md` — `resolve-ipad-simulator.sh`, `verify-ipad-layout.sh`;
  - `docs/PRD.md` — снять «только iPhone» (~:26, ~:544);
  - отметить, что эта спека заменяет невлитые `specs/062-mac-ipad-layout` (ветка `043-mac-ipad-layout`) и `specs/063-ipad` (ветка `063-ipad-adaptation`) для iPad.

  — `#recipes/sidebar`, `#recipes/tabs` (колонки рецепта), `#menubar/view` (решения, которые фиксирует документация)
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
  - T023 → T024 → T025 → T026; T027 параллельно с T025; T028 после T024; T029 после T023–T028. Колонки T025 опираются на `detailLeftWidth` из T007.
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
