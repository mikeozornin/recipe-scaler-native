# План: iPad-адаптация — адаптивная оболочка, колонки рецептов, ассистент-инспектор

**Дата**: 2026-10-12  
**Спека**: [spec.md](./spec.md)  
**Раскладка**: [layout.md](./layout.md)  
**Задачи**: [tasks.md](./tasks.md)

## Границы

- **В scope**:
  - `TARGETED_DEVICE_FAMILY = "1,2"` для таргета `RecipeScalerNative`.
  - iPad-оболочка на `TabView(.sidebarAdaptable)` (iPadOS 26.2+): сайдбар, раздел «Коллекции», футер профиля, верхний и нижний таб-бары.
  - Раздел «Рецепты»: колонка списка и панель рецепта, рецепт в две колонки: левая фиксированная, между колонками статичная линия (решение владельца 2026-10-13 вместо перетаскиваемого разделителя Q5).
  - Ассистент — своя панель справа 340 pt рядом с `TabView` в широком окне и телефонный лист в узком (не `.inspector`: спайк S5, Р7); общий store сессии ассистента.
  - Поповеры «Коллекции», истории чатов и таймеров.
  - Правка в две колонки.
  - Ограничение ширины у «Покупок» и «Подборок»; профиль «Моё всё» в широком окне — form sheet (Р2a, Q7); импорт в form sheet.
  - Отключение встряхивания на iPad.
  - `.commands` и `keyboardShortcut`.
  - Многозадачность в одном окне с изменяемым размером: Split View, Slide Over, Stage Manager.
  - Поиск iPad-симулятора и проверочный скрипт iPad-раскладки; iPad-скриншоты App Store.
- **Вне scope**:
  - Mac и Vision Pro.
  - iPad-раскладка расширений, виджетов, Live Activity и часов.
  - Изменение логики поиска, CRDT, сервера и веба.
  - Экспорт в PDF (Q3), откат правок в режиме правки (Q2), сгенерированный аватар (Q6): этого нет на iPhone.
  - Сайдбар на iPadOS 18.0–26.1 (Q1): низкий приоритет, на потом (Р3).
  - Несколько окон. Q4: «только если дёшево»; спайк S7 показал, что дорого, сработал STOP 5 (§Результаты спайка). Отдельная спека, если понадобится.
  - Идеи на потом из спеки: ассистент «видит» рецепт; сетка карточек авторов.
- **STOP conditions** (остановиться, записать в `docs/DECISIONS.md`, спросить человека):
  1. **iPhone.** Любое расхождение на iPhone: красный `verify-ui-smoke.sh`, `AppShellNavigationSpec` или unit-тесты; отличие iPhone-скриншотов до и после (T029) — кроме осознанной правки `[RecipesRoute]`, которая не меняет пиксели.
  2. **Белый экран или некликабельный UI на iPad-симуляторе** (повтор `docs/DECISIONS.md:411`) после спайка T005/T006. Сначала — минимальная репродукция в спайке, а не обход в продакшен-коде. **Итог спайка (2026-10-12):** белого экрана нет; сработал на `.inspector` уровня `TabView` и на варианте A (тулбары под таб-баром), снят заменой — своя панель ассистента (Р7) и вариант B (Р5).
  3. **Вложенная навигация.** И вариант A (`NavigationSplitView` внутри `Tab`), и вариант B (два `NavigationStack` в `HStack`) ломают панели инструментов, `.searchable` или переходы. **Не сработал** (S4): A сломан, B работает.
  4. **Коллекции в сайдбаре.** `TabSection` с динамическими коллекциями не работает без дублирования стека рецептов на каждую коллекцию (утечки, двойная подписка на YDoc). Тогда коллекции переезжают в меню заголовка колонки списка, а сайдбар остаётся без раздела — это отклонение от прототипа, нужно решение человека.
  5. **Несколько окон** требуют переноса `AppShellCoordinator` из общего `AppContainer` (`RecipeScalerNativeApp.swift:121`, `AppContainer.swift:65`) в отдельную сцену. По умолчанию это STOP для мультиоконности (Q4); одно окно с изменяемым размером остаётся в scope. **Сработал** (S7, 2026-10-12): мультиоконность вне scope, `UIApplicationSupportsMultipleScenes` не добавляется.
  6. **Устаревшие API.** Нужный API есть только в beta-SDK или требует поднять минимальную iOS выше 17.0.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Документы, схема Yjs и запись не меняются. Новая коллекция из сайдбара идёт через существующий `syncService.createFolder(name:)` (`CollectionsRootView.swift:475`). Правки рецепта — те же телефонные компоненты. |
| Web parity | N/A | Только нативная раскладка; веб не меняется. Аватар — телефонный (фото или `person.circle.fill`), нового рисования аватара нет (Q6). |
| Offline-first | PASS | Колонки, инспектор и поповеры работают на локальных данных. Футер профиля офлайн показывает номер аккаунта и `person.circle.fill` (FR-004). Сетевые действия (импорт, Вкусвилл) отключаются, как на iPhone. |
| Native UI | PASS | `TabView(.sidebarAdaptable)`, `Tab`/`TabSection`, `.tabPlacement(.pinned)`, `.tabViewSidebarBottomBar`, `tabViewBottomAccessory`, `.popover`, `.presentationSizing(.form)`, `.commands`, `keyboardShortcut`, `NavigationStack`. Системные `.inspector` на уровне `TabView` и `NavigationSplitView` внутри `Tab` отвергнуты спайком (S4, S5): на iPadOS 26.3 они ломают верхние отступы тулбаров. Замена — своя панель ассистента и колонки на двух `NavigationStack`. Шрифт Martian через `AppTypography`. |
| Phased delivery | PASS | 7 историй, каждая выпускается отдельно (spec.md); US1 — минимальный выпуск. Сначала спайк, вёрстка после него. |
| i18n | PASS | Новые строки — ключи в `Localizable.xcstrings` (en + ru), телефонные ключи переиспользуются (FR-032); `bash scripts/lint-i18n.sh`. |
| Documentation | PASS | spec.md, plan.md, tasks.md, layout.md; записи в `docs/DECISIONS.md`: по итогам спайка (колонки — вариант B, своя панель ассистента, одно окно) — 2026-10-12; оболочка, старый путь, разделитель — T054; `docs/AGENT-WORKFLOW.md` (iPad-симулятор) — T054. |

## Очерёдность

1. **Setup (T001–T004).** Скрипты iPad-симулятора, семейство устройств, проверка расширений. Без них нечем проверять.
2. **Foundational (T005–T011)** — сделано.
   - Спайк оболочки и контента на живом iPad-симуляторе (T005, T006) — вердикты в §Результаты спайка. Белого экрана из `DECISIONS.md:411` нет.
   - Чистая политика раскладки, режим раскладки в environment, типизированный путь рецептов, адаптивные модификаторы показа.
   - Всё остальное зависит от этого шага.
3. **US1 (T012–T022, T019a)** — оболочка, включая лист профиля. Без неё нет iPad-выпуска. Первый шаг T014 — проверка динамической видимости «Профиля» и «Ассистента» (§Непроверенное).
4. **US2 (T023–T031)** — колонки рецептов по варианту B (Р5). Зависит от T008–T010.
5. **US3 (T032a, T032–T035)**, **US4 (T036–T040)**, **US5 (T041–T044)** — независимы друг от друга, все после US2: им нужна панель рецепта и правило ширины. В US3 сначала общий store сессии ассистента (T032a), потом панель.
6. **US6 (T045–T048)** — меню и клавиатура. Публикует действия из US1–US5, поэтому после них.
7. **US7 (T049–T052)** — матрица многозадачности в одном окне (STOP 5: несколько окон вне scope), ландшафт и старый путь.
8. **Polish (T053–T057)** — строки, скриншоты App Store, документация, полный прогон, ревью.

## Архитектурные решения

### Р1. Режим раскладки — одна точка решения

`AppLayoutMode` (`.phone` / `.padRegular`) вычисляется один раз в `ContentView.rootChrome` (`ContentView.swift:192-210`):

```swift
idiom == .pad && horizontalSizeClass == .regular ? .padRegular : .phone
```

Значение передаётся через `EnvironmentValues`. Все iPad-ветки читают только его. Модель устройства и ориентация в решениях не участвуют (FR-030).

- **iPhone всегда `.phone`** — это главный инвариант.
- iPad в узком окне тоже `.phone`: работают телефонные пути.

Ширины внутри `.padRegular` измеряются (`onGeometryChange` на iOS 18+, `GeometryReader` в фоне на iOS 17) и проходят через чистую функцию `IPadLayoutPolicy` (layout.md §Токены).

### Р2. Оболочка

На iOS 26.2+ и iPad `AppShellView.tabView` (`AppShellView.swift:690-697`) идёт в новый `IPadAdaptiveTabView`. iPhone остаётся на `modernTabView` (`:700`) без изменений, iOS < 26.2 — на `legacyTabView` (`:790`).

`IPadAdaptiveTabView`:

- `TabView(selection:)` + `.tabViewStyle(.sidebarAdaptable)`.
- Вкладки «Подборки», «Рецепты», «Покупки».
- **Плейсмент таб-бара** (S2). Читать — `@Environment(\.tabBarPlacement)` на странице вкладки (`.topBar` ↔ `.sidebar`, `@available` iOS 18+; `reportsSidebar`, `RootView.swift:311-327`). Заголовок сайдбара для этого не годится: UIKit выдвигает сайдбар без изменения его геометрии. Менять — `UITabBarController.sidebar.isHidden`, контроллер ищется через `TabBarDiscovery` от `window.rootViewController`. Сайдбар плавает поверх контента, если `selectedViewController.view.safeAreaInsets.left < 60`. На 834 pt в портрете он плавает всегда, `sidebar.preferredLayout = .tile` игнорируется.
- «Профиль» и «Ассистент» — `.tabPlacement(.pinned)` + `.defaultVisibility(sidebarShown ? .hidden : .automatic, for: .sidebar)`. `.pinned` даёт иконки без подписи у правого края верхнего бара (S1, `s1-11`). Без динамической видимости в сайдбаре они остаются строками у футера (`s1-12`). Статичный `.hidden` для `.sidebar` прячет вкладку и из верхнего бара — как в Scrapp (`RootView.swift:240-244`) и в спайке. Сочетание динамической видимости с `.pinned` спайк **не проверял** — это первый шаг T014 (§Непроверенное).
- `sidebarShown` — плейсмент `== .sidebar`.
- `TabSection("collections.title")`: по `Tab` на каждую коллекцию, `.defaultVisibility(.hidden, for: .tabBar)`, `.sectionActions` с «Новая коллекция». **Только при `horizontalSizeClass != .compact`** (S3): в compact `.sidebarAdaptable` расплющивает все вкладки в нижний бар, включая скрытые для `.tabBar` и `.sidebarOnly`, и коллекции с «Ассистентом» уезжают в «Ещё» (`s3-02`). Без секции в compact 5 вкладок, как на iPhone (`s3-04`).
- **Бейджи** («Рецепты», «Покупки», коллекции) — только при плейсменте `.sidebar`, иначе 0: иначе они попадают в верхний бар (S1, `s1-11` / `s1-12`).
- `.tabViewSidebarBottomBar` — футер профиля, только при `.padRegular`; тап открывает лист профиля (Р2a). Программный выбор из футера не закрывает плавающий сайдбар (системный тап по строке закрывает). Поэтому после тапа: если сайдбар плавает поверх контента — `sidebar.isHidden = true` (S1, обход 3).
- Тот же `MobileTimerAccessoryModifier` (`:1029-1043`). `tabViewBottomAccessory` есть и в режиме сайдбара: аксессуар встаёт правее сайдбара и не затемняется (S6, `s6-05`). Своя капсула не нужна.
- На `TabView` **не** ставим `.inspector`: он обнуляет верхний safe area у всех вкладок, кроме первой (S5, STOP 2). Ассистент — Р7.

Содержимое вкладок — те же корневые view, что в `modernTabBar` (`:709-770`). Общие построители выносятся из `AppShellView` в `AppShellTabRoots`, чтобы не копировать.

Выбор хранит `IPadShellItem`:

```swift
enum IPadShellItem: Hashable {
    case tab(AppTab)
    case collection(String)
}
```

Это вычисляемая привязка поверх `coordinator.selectedTab` и `coordinator.recipesPath`, второго источника правды нет:

- **Чтение:** если плейсмент `.sidebar`, `selectedTab == .recipes` и в пути есть `.folder(id)` пользовательской коллекции — `.collection(id)`; иначе `.tab(selectedTab)`. При `.topBar` и в compact выбранная коллекция читается как `.tab(.recipes)`, а сама коллекция остаётся в пути. Причина (S1, обход 4): выбранный `Tab` коллекции в режиме верхнего бара вытаскивает в бар всю группу «Коллекции» с кнопкой «‹» (`s1-20`), и `.tabPlacement(.sidebarOnly)` не помогает (`s1-15`). В compact секции нет вовсе (S3). Привязка получает плейсмент параметром, как `isSplitActive`.
- **Запись `.collection(id)`** зависит от режима. Привязка получает `isSplitActive`: `true`, только когда раздел «Рецепты» рисует `IPadRecipesSplitView` (`.padRegular`, после T024); в US1, в compact и на телефонном стеке — `false`.
  - `isSplitActive == false`: `selectedTab = .recipes`, путь = `[.folder(id)]` — телефонный экран коллекции в стеке (spec.md US1, сценарий 5).
  - `isSplitActive == true`: `selectedTab = .recipes`, путь = `[.folder(id), .recipe(recipeId: первый рецепт коллекции, folderContext: id)]` — колонка коллекции и её первый рецепт (US2, сценарий 5). Пустая коллекция — `[.folder(id)]`.
  - Оба случая — `IPadShellItemTests/testCollectionMapsToRecipesPath`.
- **Запись `.tab(.assistant)`:** выбор не меняется, ассистент открывается или закрывается — как `handleTabSelection` (`AppShellCoordinator.swift:147`).
- **Запись `.tab(.profile)` при `.padRegular`:** выбор не меняется, открывается лист профиля (Р2a).

Содержимое невыбранных `Tab` коллекций — пустое (`Color.clear`), чтобы не держать несколько стеков рецептов (STOP 4). Спайк подтвердил: строится только выбранная вкладка, лишних стеков нет, STOP 4 не сработал.

**Футер и сайдбар — UIKit-обходы.** `sidebar.isHidden` и `TabBarDiscovery` — единственный UIKit-код оболочки. Он живёт в одном помощнике (`IPadSidebarControl`, рядом с `IPadAdaptiveTabView`) и вызывается только при `.padRegular` на iPadOS 26.2+. Если контроллер не найден — ничего не делаем и пишем в лог (сайдбар остаётся открытым, это не блокирует).

### Р2a. Профиль — form sheet в широком окне (Q7, как в Scrapp)

Образец — `scrapp-ios/Scrapp/RootView.swift` (только чтение):

- `@State profileSheet` (:55);
- `.tabViewSidebarBottomBar { SidebarProfileRow }` при сайдбаре (:102-109, сама строка — :329-362);
- перехват выбора в `.onChange(of: tab)` (:113-121);
- переход size class в `.onChange(of: sidebar)` (:132-137);
- `.sheet(isPresented: $profileSheet) { NavigationStack { ProfileView.toolbar { Done } }.presentationSizing(.form) }` (:163-178);
- видимость вкладки (:238-244).

У нас то же самое, но состояние живёт в `AppShellCoordinator`, а решение — в чистой функции.

**Состояние** (`AppShellCoordinator`):

- `isProfileSheetPresented: Bool` — единственный источник правды для листа;
- `lastNonProfileTab: AppTab` — обновляется при каждой записи `selectedTab` в вкладку, отличную от `.profile`; по умолчанию `.recipes`. Фиктивные «Ассистент» и «Импорт» в `selectedTab` не попадают (`handleTabSelection`, `:149-177`), поэтому не учитываются.

**Правило** — `IPadProfileSheetPolicy` (`RecipeScalerNative/Routing/IPadProfileSheetPolicy.swift`):

```swift
enum IPadProfileSheetPolicy {
    /// selected == .profile в .padRegular → (previous ?? .recipes, presentsSheet: true); иначе без изменений.
    static func resolve(selected: AppTab, previous: AppTab?, layoutMode: AppLayoutMode)
        -> (selected: AppTab, presentsSheet: Bool)
}
```

Координатор применяет его в `normalizeProfileSelection(previous:layoutMode:)`. Если `presentsSheet`, он ставит `selectedTab` и `isProfileSheetPresented = true`.

**Где вызывается** — одна точка для всех входов, как `onChange(of: tab)` в Scrapp:

- `IPadAdaptiveTabView` и `legacyTabView` при `.padRegular`: `.onChange(of: coordinator.selectedTab) { old, _ in normalize(previous: old, …) }`. Так покрыты тап по вкладке «Профиль» в верхнем баре, `requestRemindersSetup()` (`:203-206`, кнопка «Настроить Напоминания» в «Покупках»), ⌘4 (Р8) и `openDebugTabIfNeeded(.profile)` (`-OpenTab=profile`).
- `.onChange(of: layoutMode, initial: true)`: при переходе в `.padRegular` с выбранным «Профилем» — `previous: lastNonProfileTab`. Это FR-004b; заодно `-OpenTab=profile` на старте в широком окне сразу открывает лист.
- При переходе в `.phone` ничего не делаем: лист остаётся открытым, как в Scrapp (там `onChange(of: sidebar)` не трогает `profileSheet`). `iPadFormSheet()` завязан на idiom, поэтому содержимое листа не пересоздаётся. Система в compact показывает form sheet на всю ширину.

**Перехват выбора.** Привязка `IPadShellItem` при записи `.tab(.profile)` в `.padRegular` сразу ставит `isProfileSheetPresented = true`, не трогая `selectedTab`, — как у `.tab(.assistant)`.

Урок Scrapp (`RootView.swift:113-114`): если системный таб-бар после отказа в привязке оставляет на экране пустую страницу «Профиля», делаем как там. Привязка пропускает выбор, а `onChange` выше возвращает прежнюю вкладку и открывает лист. Какой из двух вариантов работает, решает проверка на симуляторе в T019a. В `.padRegular` содержимое `Tab` «Профиль» — `Color.clear`: оно не показывается, и второй `AccountView` не грузит профиль за листом. В `.phone` (compact) там телефонный `AccountView` из `AppShellTabRoots`.

**Футер.** `IPadSidebarProfileFooter` — `Button`, вызывает `coordinator.presentProfileSheet()`, а если сайдбар плавает поверх контента — ещё и прячет его через `IPadSidebarControl` (Р2, S1 обход 3; иначе лист открывается под затемнением открытого сайдбара). Выбранным не бывает (в Scrapp «it's never selected»), `.hoverEffect`, `accessibilityIdentifier` `ipad.sidebar.profileFooter`.

**Лист** — на уровне `IPadAdaptiveTabView` (и `legacyTabView` для Р3):

```swift
.sheet(isPresented: $coordinator.isProfileSheetPresented, onDismiss: { coordinator.profileSheetDidDismiss() }) {
    AccountView(auth:, timer:, vkusvillSettings:, performLogoutTeardown:, onDone: { coordinator.isProfileSheetPresented = false })
        .iPadFormSheet()   // AdaptivePresentation.swift: .presentationSizing(.form) на iPad, iOS 18+
}
```

- `AccountView` уже держит свой `NavigationStack` (`AccountView.swift:113`) и заголовок «Моё всё» (`.localizedNavigationTitle("account.title")`, `:172`). Второй `NavigationStack` снаружи не оборачиваем: во вложенном стеке тулбар внешнего не виден.
- «Готово» — новый необязательный параметр `onDone: (() -> Void)?`. Если он задан, `AccountView` добавляет `ToolbarItem(placement: .confirmationAction) { Button("common.done") }` — тот же ключ, что у его вложенных листов (`:1013`). На iPhone и во вкладке `nil`: дерево не меняется.
- Зависимости кнопки передаются явно (ловушка iOS 26 ниже).
- Тап мимо листа закрывает его системно (form sheet), `interactiveDismissDisabled` не ставим.
- `.id(locale)` не нужен: `AccountView` уже перерисовывает строки при смене языка в приложении. Проверяется вручную в T053.
- `pendingRemindersSetup` листовой `AccountView` должен обработать при появлении. Сейчас флаг ловит только `onChange` (`:288`), а лист создаётся, когда флаг уже стоит. Поэтому `onChange(..., initial: true)` или вызов `consumePendingRemindersSetupIfNeeded` в `.task`; на iPhone поведение не меняется (T019a).

**Обновление футера.** `profileSheetDidDismiss()` увеличивает `profileSheetRevision`. Футер грузит профиль в `.task(id: FooterKey(userId, revision))`, поэтому после смены «Публичный профиль» или имени в листе показывает новые имя и аватар.

**Стратегия тестов:**

- Unit — `RecipeScalerNativeTests/IPadProfileSheetPolicyTests.swift`:
  - `testRegularProfilePresentsSheetAndKeepsPrevious`;
  - `testRegularProfileWithoutPreviousFallsBackToRecipes`;
  - `testPhoneProfileSelectsTab`;
  - `testNonProfileSelectionUnchanged`.
- Unit — `AppShellCoordinatorTests`:
  - `testWideningOnProfileTabRestoresPreviousAndPresentsSheet`;
  - `testNarrowingKeepsProfileSheet`;
  - `testRemindersSetupInRegularPresentsSheet`;
  - `testLogoutDismissesProfileSheet`.
- Unit — `IPadShellItemTests/testProfileInRegularDoesNotChangeSelection`.
- UI — `IPadShellSpec`:
  - `testFooterOpensProfileSheet`: лист с «Моё всё» и «Готово», выбор в сайдбаре прежний, «Готово» закрывает;
  - `testTopBarProfileOpensSheet` (`-IPadSidebarHidden=1`);
  - `testSidebarHasNoProfileTab`;
  - `testProfileHasNoShakeRow` — в листе.
- Раскладка: `verify-ipad-layout.sh` снимает `profile-public` / `profile-private` как лист поверх `#recipes/sidebar` и `#recipes/tabs` (`-OpenTab=profile` в широком окне → лист через нормализацию) и страницу вкладки в окне ½.

### Р3. Старый путь (iPadOS 17.0–26.1) — решено (Q1)

Оболочка не меняется: `legacyTabView` с `.tabItem`. Система сама рисует верхний таб-бар на iPadOS 18+ и нижний на 17. Сайдбара, раздела «Коллекции» и футера нет; коллекции доступны телефонным экраном.

Колонки рецепта, политика ширины, панель ассистента (обычный `HStack`, без API 26.x), поповеры, form sheet и ограничение ширины работают везде, где `AppLayoutMode == .padRegular`. Лист профиля тоже (Р2a): вкладка «Профиль» системного таб-бара открывает его тем же правилом координатора. Капсулы таймеров нет — как на старом пути iPhone.

Почему так (пользователь согласился, Q1):

- на iPadOS 17 API сайдбара (`.sidebarAdaptable`, `Tab`, `TabSection`) нет совсем;
- на 18.0–26.1 API есть, но iPad-оболочка встраивается за общий гейт `#available(iOS 26.2, *)` (`AppShellView.swift:680-697`): новый путь держит панель таймеров на `tabViewBottomAccessory` / `safeAreaBar`, а их до 26.2 нет.

**На потом, низкий приоритет:** сайдбар можно расширить на iPadOS 18+ третьим построителем таб-бара (`Tab`/`TabSection` без `tabViewBottomAccessory`, таймеры как на старом пути). В v1 не делается.

### Р4. Состояние раздела «Рецепты»

`AppShellCoordinator.recipesPath` переходит с `NavigationPath` на `[RecipesRoute]` (`AppShellCoordinator.swift:68`). Это безопасно: в стек рецептов кладутся только `RecipesRoute` — `RecipeListView.swift:501/:535/:624`, `CollectionFolderView.swift:370/:491`, `CollectionsRootView.swift:219/:352`, единственный `navigationDestination(for: RecipesRoute.self)` в `RecipeListView.swift:299`. Потоки разметки описания держат свои `NavigationStack` (`DescriptionMarkupFlow.swift:138/:188/:342/:411`).

Чистые функции `RecipesSelection` (новый файл):

- `selection(from path) -> (collectionId?, recipeId?, openInEditMode)` — последний `.folder` и последний `.recipe`;
- `path(for selection)`;
- `selectingRecipe(_:in:)`, `selectingCollection(_:firstRecipeId:)`.

iPhone пушит в массив так же, как в `NavigationPath`. iPad читает и пишет тот же массив. Поэтому рецепт и коллекция переживают смену size class (FR-018), а диплинки (`AppShellCoordinator.swift:237-264`, `:389`, `:420`) работают без изменений.

### Р5. Колонки раздела «Рецепты»

**Решено спайком T006 (S4): вариант B.** Записано в `docs/DECISIONS.md` (2026-10-12).

- **A — отвергнут.** `NavigationSplitView` из двух колонок внутри `Tab`. После показа и скрытия сайдбара (кнопкой или программно) nav bar-ы колонок остаются со старым верхним отступом и уезжают под плавающий таб-бар: y=46 вместо 90, «…» и ✦ ложатся на «Профиль» и «Ассистента» (`s2-02`, `s4-03`). Лечится только сменой вкладки. Не помогли `setNeedsLayout`, «подпрыгивание» таб-бара, `.id(tabBarPlacement)` на сплите; `additionalSafeAreaInsets` перебарщивает (y=122). Источник — вложенный `UISplitViewController` внутри `UITabBarController`. Баг стабилен на основном сценарии (открыть и закрыть сайдбар в портрете).
- **B — выбран.** `HStack` из двух `NavigationStack`: тулбары в порядке и до, и после переключения сайдбара (`s4-01`, `s4-02`), с панелью ассистента тоже (тулбар y=100, `insetT=96`). STOP 3 не сработал.

```swift
HStack(spacing: 0) {
    if listMode == .inline {
        NavigationStack { RecipeListView(columnMode: true) }   // поиск — во внешнем состоянии
            .frame(width: IPadLayoutMetrics.listColumnWidth)   // 320
        Divider()
    }
    NavigationStack(path: $detailPath) {
        YDocRecipeDetailView(recipeId: id).id(id)
            .toolbar { ToolbarItem(placement: .topBarLeading) { listButton } }  // sidebar.left, если список не inline
    }
}
.overlay(alignment: .leading) {
    if listMode == .overlay {   // аналог .prominentDetail
        ZStack(alignment: .leading) {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { listMode = .hidden }
            NavigationStack { RecipeListView(columnMode: true) }
                .frame(width: IPadLayoutMetrics.listColumnWidth).background(.background).shadow(radius: 12)
        }
    }
}
```

- **`listMode`** — `.inline` / `.hidden` / `.overlay`. `.inline`, если `IPadLayoutPolicy` говорит `listShown`. Иначе `.hidden`; кнопка «Список рецептов» переводит в `.inline`, если список помещается, иначе в `.overlay`. Тап по затемнению или выбор рецепта в `.overlay` → `.hidden`. Флаг «список спрятан пользователем» — в `AppShellCoordinator` (Р4).
- **Что делаем руками** (цена B): кнопку «Список рецептов» (`sidebar.left`, `ToolbarItem(placement: .topBarLeading)`, `s4-05`), выезжающий поверх список — `.overlay` с затемнением 0.25 и шириной 320 (`s4-06`), стиль колонки — фон, ширину и разделитель 1 pt.
- **Поиск.** `.searchable` колонки списка в B — лупа в тулбаре колонки, раскрывается и фильтрует (`s4-04`); встроенного поля, как у сайдбар-колонки A, нет. Состояние поиска держится **вне** `NavigationStack` списка (во вью-модели списка или в `@State` родителя): тогда запрос переживает `.inline` ↔ `.hidden` ↔ `.overlay`. Спайк это подтвердил.
- **Вид не меняется**: список 320 + разделитель 1 + панель, как в layout.md. Отличия от A невидимы пользователю, кроме формы поля поиска.

Колонка списка — `RecipeListView` в «режиме колонки»: тот же список, поиск, меню «+». Строки выбирают рецепт (`Button` и выделение) вместо `NavigationLink(value:)` (`RecipeListView.swift:535`) только при `.padRegular`. Плитка папок (`viewModeMenu`, `:403-435`) в колонке не показывается.

Панель рецепта — `YDocRecipeDetailView(recipeId:)` с `.id(recipeId)` в корне своего стека. Выбор рецепта меняет корень, а не путь стека панели (`detailPath` — только для переходов внутри панели, если они есть).

### Р6. Рецепт в две колонки

Тело `YDocRecipeDetailView` (`YDocRecipeDetailView.swift:274-414`) раскладывается на два `@ViewBuilder`:

- **левая колонка:** `RecipeDetailImageSection` (:280), заголовок или `editHeader` (:301-310), `servingsBlock` (:312), `YDocIngredientsEditSection` (:317) / `YDocIngredientsSection` (:374), `nutritionBlock` (:392-396);
- **правая колонка:** `RecipeDescriptionEditorBlock` (:400) / `StepsSection` (:414).

Одна колонка — `VStack` в прежнем порядке с прежними отступами: на iPhone дерево view эквивалентно текущему.

Две колонки (`.padRegular` и панель ≥ 720) — `HStack(spacing: 0)` из двух `ScrollView`:

- левая — ширина `IPadLayoutPolicy.detailLeftWidth(detailWidth:)`: `min(400, панель − 1 − 320)`, то есть 400, на границе 720 — 399; правой остаётся не меньше 320;
- статичная линия 1 pt (`Color(.separator)`) между колонками (см. ниже);
- правая: текст шагов не шире 660 с отступами секций 16, как слева, и верхним отступом, который ставит «Инструкции» на линию первого элемента левой колонки (`RecipeStepsColumnMetrics`; решение владельца 2026-10-13, до него было 32 по бокам);
- общий `ScrollViewReader` над обеими колонками.

**Линия между колонками (FR-012a)** — решение владельца 2026-10-13, заменяет перетаскиваемый разделитель Q5:

- только линия 1 pt: без ручки, `DragGesture`, `@AppStorage` и элемента VoiceOver; ширина нигде не сохраняется;
- содержимое левой колонки не шире предложенной ширины. Вертикальный `ScrollView` с более широким содержимым расширяется и центрирует его, и колонка уезжает влево. Единственный несжимаемый элемент — выбор базы КБЖУ (`UISegmentedControl` с явными ширинами сегментов). Строка «КБЖУ на» + выбор: 390,5 pt в en, 374 в ru, поэтому в `RecipeNutritionBlockView` она собрана через `ViewThatFits`: `HStack`, а если не помещается, `VStack` с выбором под заголовком. Где строка помещается, вид прежний; на iPhone 402 pt не меняется ни в одном языке.

Переносы в правую колонку:

- `DetailScrollViewProbe` (:277) — для прокрутки без рук (FR-026);
- `formattingBarInset` (`:505-507`, `:776-789`) — через `.safeAreaInset(edge: .bottom)` правого `ScrollView` (FR-028).

`AwakeScrollChromeModifier` (:761) остаётся на внешнем контейнере, поэтому полоса готовки тянется на обе колонки (FR-023). `.mobileTimerPanelBottomPadding` действует на обе колонки.

### Р7. Показ: панель ассистента, поповеры, form sheet

- **Ассистент — своя панель справа, не `.inspector`** (спайк S5, `docs/DECISIONS.md` 2026-10-12). `.inspector` на уровне `TabView` обнуляет верхний safe area у всех вкладок, кроме первой, и у вкладок коллекций (STOP 2, `s1-05`). `.inspector` в каждой вкладке инсеты не ломает, но пересоздаёт ассистента при смене вкладки, и черновик теряется (`s5-03`–`s5-05`). Своя панель проверена: инсеты в порядке, панель переживает смену вкладок (`s5-06`, `s5-07`), в compact — лист (`s5-08`).

  Один `showAssistant` (`AppShellView.swift:106`), два показа:

  ```swift
  HStack(spacing: 0) {
      tabView                                     // TabView(.sidebarAdaptable) или legacyTabView
      if showAssistant && layoutMode == .padRegular {
          Divider().ignoresSafeArea()
          AssistantSheet(session: assistantSession, presentation: .inspector)
              .frame(width: IPadLayoutMetrics.inspectorWidth)   // 340, имя константы прежнее
              .transition(.move(edge: .trailing))
      }
  }
  .animation(.snappy, value: showAssistant)
  ```

  - В `.phone` и в compact — существующий `AssistantSheetModifier` (`:1046-1072`) с `isPresented: layoutMode == .padRegular ? .constant(false) : $showAssistant`.
  - Панель занимает 340 pt из ширины окна; `IPadLayoutPolicy.contentWidth(…, inspectorVisible:)` вычитает её так же, как раньше вычитал колонку инспектора: матрица layout.md не меняется. Константа остаётся `IPadLayoutMetrics.inspectorWidth`; в тексте «инспектор» = эта панель.
  - Внутри панели — содержимое `AssistantSheet`. При `AssistantPresentation == .inspector` добавляется ×, а история (`AssistantSheet.swift:129`) показывается поповером с содержимым `AssistantThreadListSheet`.
- **Общая сессия ассистента** (новое, T032a). Панель и лист — разные экземпляры view. Сейчас `AssistantSheet` держит всю сессию в `@State` (`:26-56`): `threadId`, `threads`, `messages`, `input`, `attachments`, `isSending`, `streamTask`, `bootstrapTask`, `externalSendTask`. В `onDisappear` (`:185-210`) он сохраняет `threadId` в `AssistantSessionStore` и отменяет задачи. Поэтому переход панель ↔ лист (смена size class) теряет черновик и обрывает ответ. `AssistantSessionStore` (`Services/AssistantSessionStore.swift`) хранит только `threadId` и `lastOpenedAt`.
  - Новый `@MainActor @Observable final class AssistantSessionModel` держит `threadId`, `threads`, `messages`, `input`, `attachments`, `isSending`, задачи стрима и бутстрапа.
  - Владелец — `AppContainer` (одна сессия на приложение: окно одно, STOP 5). Модель передаётся в `AssistantSheet` явно, параметром `session:`, а не через `@Environment` (ловушка iOS 26, ниже).
  - Задачи отменяет модель: при явном закрытии ассистента (×, свайп листа, `showAssistant = false`), при смене `coordinator.assistantSessionEpoch` (`teardownForSessionInvalidation`) и при logout. `onDisappear` view больше не отменяет стрим: при переходе панель ↔ лист старый view исчезает, а ответ должен дойти. `threadId` по-прежнему пишется в `AssistantSessionStore` для восстановления после перезапуска.
  - На iPhone поведение то же: лист открылся — сессия продолжилась, закрылся — задачи отменены, тред сохранён. Отличие только в том, что черновик `input` переживает закрытие и повторное открытие листа (сейчас он сбрасывается); это совпадает с ожиданием «тот же чат» (FR-019) и проверяется в T035.
  - Если перенос сессии окажется дороже, чем выглядит (например, `AssistantSheet` завязан на `@State` в десятках мест), — остановиться и спросить. Деградация «переход панель ↔ лист теряет черновик, тред сохраняется» допустима только с согласия человека.
- **Поповеры.** `.adaptivePopover(isPresented:...)`: при `.phone` — тот же `.sheet` с той же хромой (`appOpaqueSheetPresentation()`), при `.padRegular` — `.popover`. Применяется к:
  - `CollectionAssignSheet` из «…» (`RecipeDetailActionsMenu.swift:61-62`, поповер 300 pt). Спайк: поповер от пункта `Menu` работает и привязан к «…» (S6, `s6-04`);
  - истории ассистента;
  - таймерам: тап по капсуле на `.padRegular` открывает поповер 380 pt с `MobileTimerPanel(.insetExpanded)` вместо раскрытой панели (`AppShellView.swift:650-664`).
- **Поповер таймеров — на уровне оболочки** (S6). `.popover` внутри `tabViewBottomAccessory` сломан: тап проходит, поповер не появляется. Состояние `timerPopoverShown` живёт в оболочке, капсула в аксессуаре только ставит флаг. Поповер прикреплён к невидимому якорю, фрейм которого берётся из фрейма аксессуара: `onGeometryChange` → `.popover(attachmentAnchor: .rect(.rect(frame)), arrowEdge: .bottom)`. Фиксированная точка снизу по центру не годится: открытый сайдбар сдвигает аксессуар вправо (`s6-06`). `.presentationCompactAdaptation(.sheet)` на случай compact.
  - Аксессуар есть и в режиме верхнего бара, и в режиме сайдбара (`s6-01`, `s6-05`). Своя капсула `.overlay(alignment: .bottom)` не нужна.
  - Однажды в спайке аксессуар пропал после тапа по координате; не повторилось. При реализации T038 — перепроверить серией открытий и закрытий.
- **Профиль.** `.sheet` + `.iPadFormSheet()` с телефонным `AccountView` и «Готово» — Р2a.
- **Импорт.** `ImportRecipeSheet` (`ImportRecipeSheet.swift:216`) на `.padRegular` — `.presentationSizing(.form)` (iOS 18+; на iOS 17 iPad сам показывает form sheet). Если окажется, что `detents: [.large]` уже даёт form sheet, правка не нужна (T020).

### Р8. Меню и клавиатура

`.commands` на `WindowGroup` (`RecipeScalerNativeApp.swift:176`). Действия публикуются через `.focusedSceneValue`:

- `AppCommandActions` — из `AppShellView`;
- `RecipeCommandActions` — из `YDocRecipeDetailView`.

Публикация идёт только при `idiom == .pad`. На iPhone значения `nil`, команды неактивны, поведение не меняется. Таблица команд — layout.md §Меню; в меню только действия, которые есть на iPhone («Экспорт в PDF…» не делается, Q3). ⌘F — `.searchFocused` (iOS 18+); на iOS 17 команды «Найти» нет.

### Р9. Встряхивание

`ShakeToOpenAssistantPreference` получает чистую проверку `isActive(idiom:)` = `isEnabled && idiom != .pad`. `handleDeviceShake` (`AppShellView.swift:214`) и обработчик запроса на встряхивание (`:205`) используют её вместо `isEnabled`. Строку `AccountView.swift:579-585` на iPad не показываем. Ключ `shakeToOpenAssistantEnabled` (`ShakeToOpenAssistantPreference.swift:11`) не трогаем.

### Ловушка iOS 26: environment-observable в тулбаре

В тулбарах и аксессуарах нельзя читать `@Environment(SomeObservable.self)`: это ловушка iOS 26, описанная в `ShoppingListView.swift:26-27` и `RecipeDetailShareButton.swift:15-16`. Зависимости передаются явно — это касается новых кнопок ✦, футера сайдбара, «Готово» листа профиля и `sectionActions`.

### Результаты спайка (T005 — S1, S2, S3, S7; T006 — S4, S5, S6)

| # | Вопрос | Вердикт | Решение |
|---|--------|---------|---------|
Спайк выполнен 2026-10-12: Xcode 26.3, iPad Pro 11″ (834 × 1210), iPadOS 26.3. Код спайка — выбрасываемый, в ветку фичи не вливается. Подробности и скриншоты: `tmp/ipad-research/spike-verdicts.md`, `tmp/ipad-research/spike/`.

| # | Вопрос | Вердикт | Решение |
|---|--------|---------|---------|
| S1 | `.sidebarAdaptable` + `TabSection` с динамическими коллекциями + `.sectionActions` + `.tabViewSidebarBottomBar` на iPad-симуляторе 26.x: нет белого экрана, всё кликается | VERIFIED (с обходами) | Р2. Белого экрана нет. Обходы: бейджи только при плейсменте `.sidebar`; Профиль и Ассистент — `.tabPlacement(.pinned)`; выбор из футера прячет плавающий сайдбар (`IPadSidebarControl`); выбранная в режиме верхнего бара коллекция отображается как `.recipes` + `.folder(id)`; без `.inspector` на `TabView`. STOP 4 не сработал. |
| S2 | Можно ли читать и менять видимость сайдбара (⌃⌘S, свернуть в правке, меню заголовка списка только при скрытом сайдбаре) | CHECKED (портрет); ландшафт INCONCLUSIVE | Читаем `@Environment(\.tabBarPlacement)`, меняем `UITabBarController.sidebar.isHidden` через `IPadSidebarControl`. ⌃⌘S — своя команда, сайдбар в правке сворачивается, меню заголовка — при `.topBar`. На 834 портрет сайдбар всегда плавает поверх затемнённого контента, `.tile` игнорируется. Ландшафт — §Непроверенное. |
| S3 | В узком окне `.sidebarAdaptable` даёт нижний таб-бар, как `modernTabView` на iPhone (минимизация, аксессуар таймеров) | VERIFIED (с обходом) | Нижний бар и аксессуар есть. В compact `TabSection` не строим, иначе коллекции и Ассистент уходят в «Ещё». `traitOverrides` не помогают. |
| S4 | Вариант A (`NavigationSplitView` в `Tab`) или B (`HStack` из двух стеков): тулбары колонок, `.searchable`, `.prominentDetail` поверх | A — FAILED; B — VERIFIED | Р5 = B. У A тулбары колонок уезжают под таб-бар после переключения сайдбара. STOP 3 не сработал. |
| S5 | `.inspector` на уровне `TabView`: ширина 340, открыт поверх смены вкладок, переход sheet ↔ inspector при смене size class | `.inspector` на `TabView` — FAILED (STOP 2); своя панель — VERIFIED | Р7: своя панель `HStack` 340 pt + лист в compact; сессия ассистента в общем store (T032a). |
| S6 | `.popover` от `Menu` («…») и от `tabViewBottomAccessory`; где капсула таймеров в режиме сайдбара | VERIFIED (с обходом) | Поповер из `Menu` работает. Аксессуар есть в режиме сайдбара — своя капсула не нужна. `.popover` внутри аксессуара сломан → поповер на уровне оболочки с якорем по фрейму аксессуара (Р7). |
| S7 | Сколько стоит несколько окон (общий `AppContainer`) | FAILED (дорого) | STOP 5: одно окно с изменяемым размером; несколько окон вне scope. |

Вердикты: CHECKED / VERIFIED / INCONCLUSIVE / FAILED.

**STOP:** 2 — сработал на `.inspector` уровня `TabView` и на варианте A, снят заменой (своя панель, B). 3 — не сработал. 4 — не сработал. 5 — сработал, мультиоконность вне scope. 6 — не сработал: всё использованное есть в iOS 26.2 SDK и закрыто `@available` на пути 26.2+, минимальная iOS 17.0 не меняется.

### Непроверенное

| Что | Почему не проверено | Как и когда проверяем | Если не подтвердится |
|-----|---------------------|-----------------------|----------------------|
| Ландшафт и ширины 1024/1194/1366: встаёт ли сайдбар рядом с контентом; работает ли раскладка колонок «рядом» | `requestGeometryUpdate` отказывает («windowing mode does not allow…») и в Windowed Apps, и в Full-Screen Apps | T049: повернуть Simulator.app через `osascript` (cmd+→ или меню Device › Rotate Right) и снять матрицу. Если поворот не удаётся автоматизировать — пометить в отчёте T049 и передать владельцу проверку на устройстве (human gate) | Политика колонок от этого не зависит: она считает ширину контента. Если сайдбар в ландшафте тоже плавает — матрица layout.md для 1194 пересчитывается без вычета 321 pt; решение записывается в DECISIONS |
| Динамический `.defaultVisibility(placement == .sidebar ? .hidden : .automatic, for: .sidebar)` вместе с `.tabPlacement(.pinned)` для Профиля и Ассистента | Спайк проверил только статичные варианты (`s1-11`, `s1-12`) | Первый шаг T014, до остальной оболочки: переключить сайдбар туда и обратно, убедиться, что строки «Профиль» и «Ассистент» уходят из сайдбара, а иконки в верхнем баре остаются | Остановиться и спросить: либо строки остаются в сайдбаре рядом с футером, либо ищем другой обход |
| iPadOS 18.4 — старый путь оболочки (Р3) | В спайке только 26.3 | T051 | Как в T051 |
| Эмодзи в подписях сайдбара (имена коллекций) | Не проверялось на симуляторе с нормальным эмодзи-шрифтом | T049 (ручной проход по матрице) на симуляторе с эмодзи-шрифтом или на устройстве | Записать в DECISIONS, подписи не меняем |

### Риски после спайка

- **UIKit-обход видимости сайдбара** (`sidebar.isHidden`) опирается на поиск `UITabBarController` в иерархии. Может сломаться в следующей iPadOS. Изолирован в `IPadSidebarControl`; если контроллер не найден — лог и бездействие: сайдбар остаётся системным, приложение работает.
- **Перенос сессии ассистента** в `AssistantSessionModel` трогает iPhone-путь. Митигировано: T035 и `verify-assistant.sh` на iPhone; поведение листа на iPhone эквивалентно (черновик теперь переживает закрытие).
- **Свой стиль колонки списка (B)** — фон, разделитель, выезд поверх делаются руками и могут разойтись с системными в будущих iPadOS. Митигировано: `verify-ipad-layout.sh` по состояниям прототипа.
- **Поповер таймеров** привязан к фрейму аксессуара; аксессуар однажды пропадал (S6). T038 включает серию открытий и закрытий.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative.xcodeproj/project.pbxproj` | Изменить | `TARGETED_DEVICE_FAMILY = "1,2"` для приложения (:4158, :4397, :4419, :4442); расширения и ShareExtensionUI — `"1,2"`, RecipeScalerCore — `"1,2,4"` (T004); регистрация новых файлов. |
| `RecipeScalerNative/Info.plist` | Проверить, не менять | Ориентации `~ipad` уже есть (:116-122). `UIApplicationSupportsMultipleScenes` не добавляем (STOP 5). |
| `RecipeScalerNative/Views/IPad/AppLayoutMode.swift` | Создать | Р1: режим раскладки, ключ environment, вычисление из idiom и size class. |
| `RecipeScalerNative/Views/IPad/IPadLayoutPolicy.swift` | Создать | Константы и чистая политика колонок, включая ширину левой колонки рецепта (layout.md §Токены). |
| `RecipeScalerNative/Views/IPad/AdaptivePresentation.swift` | Создать | `.adaptivePopover`, `.iPadReadableWidth(_:)`, `.iPadFormSheet()` — без эффекта при `.phone`. |
| `RecipeScalerNative/Views/IPad/IPadShellItem.swift` | Создать | Р2: выбор оболочки и вычисляемая привязка. |
| `RecipeScalerNative/Views/IPad/IPadAdaptiveTabView.swift` | Создать | Р2: `TabView(.sidebarAdaptable)`; Р2a: видимость вкладки «Профиль», лист профиля, нормализация выбора. |
| `RecipeScalerNative/Views/IPad/IPadSidebarProfileFooter.swift` | Создать | Футер профиля (FR-004); тап открывает лист профиля (Р2a). |
| `RecipeScalerNative/Routing/IPadProfileSheetPolicy.swift` | Создать | Р2a: чистое правило «вкладка „Профиль“ в `.padRegular` → лист + прежняя вкладка» (FR-004a, FR-004b). |
| `RecipeScalerNative/Views/AccountAvatarView.swift` | Создать | Телефонный аватар (фото или `person.circle.fill`), вынесенный из `AccountView` (:860-871) без изменения вида; используется в `AccountView` и футере сайдбара (FR-005). |
| `RecipeScalerNative/Views/IPad/IPadRecipesSplitView.swift` | Создать | Р5, вариант B: `HStack` из двух `NavigationStack`, `listMode` (`.inline`/`.hidden`/`.overlay`), своя кнопка «Список рецептов», выезд поверх с затемнением. Имя файла прежнее, `NavigationSplitView` внутри нет. |
| `RecipeScalerNative/Views/IPad/IPadSidebarControl.swift` | Создать | Р2: чтение плавающего сайдбара и `sidebar.isHidden` через `TabBarDiscovery`; единственный UIKit-код оболочки, только `.padRegular` и 26.2+. |
| `RecipeScalerNative/Services/AssistantSessionModel.swift` | Создать | Р7: общая `@Observable`-сессия ассистента (сообщения, черновик, вложения, задачи стрима) для панели и листа; владелец — `AppContainer`. |
| `RecipeScalerNative/Views/IPad/IPadAssistantToolbarButton.swift` | Создать | Кнопка ✦ для `.padRegular`. |
| `RecipeScalerNative/Views/IPad/IPadCommands.swift` | Создать | Р8: `FocusedValueKey`, `AppCommandActions`, `RecipeCommandActions`, `Commands`. |
| `RecipeScalerNative/Views/AppShellTabRoots.swift` | Создать | Общие корни вкладок для `modernTabBar` и `IPadAdaptiveTabView`. |
| `RecipeScalerNative/Routing/RecipesSelection.swift` | Создать | Р4: чистые функции путь ↔ выбор. |
| `RecipeScalerNative/Routing/AppShellCoordinator.swift` | Изменить | `recipesPath: [RecipesRoute]` (:68); помощники выбора; хранение флага «список спрятан»; Р2a: `isProfileSheetPresented`, `lastNonProfileTab`, `profileSheetRevision`, `presentProfileSheet()`, `normalizeProfileSelection(previous:layoutMode:)`, сброс листа в `resetShellStateForLogout` (:461). |
| `RecipeScalerNative/Views/AppShellView.swift` | Изменить | Ветка iPad в `tabView` (:690-697); панель ассистента в `HStack` рядом с `TabView` вместо `.inspector` (:426, Р7); защита от встряхивания (:214); тап по капсуле таймеров и поповер таймеров на уровне оболочки с якорем по фрейму аксессуара (:650-664, Р7); лист профиля и нормализация выбора на `legacyTabView` при `.padRegular` (Р2a, Р3); публикация команд. |
| `RecipeScalerNative/ContentView.swift` | Изменить | Режим раскладки в `rootChrome` (:192-210). |
| `RecipeScalerNative/RecipeScalerNativeApp.swift` | Изменить | `.commands` на `WindowGroup` (:176). |
| `RecipeScalerNative/Views/RecipeListView.swift` | Изменить | `Binding<[RecipesRoute]>` (:18, :40); режим колонки (выбор вместо push, :535); контекстное меню (iPad) на тех же обработчиках, что свайпы (:544-573). |
| `RecipeScalerNative/Views/CollectionsRootView.swift`, `CollectionFolderView.swift` | Изменить | Тип привязки пути; создание коллекции вынесено в общий помощник (`commitNewFolder` :458) для сайдбара. |
| `RecipeScalerNative/Views/YDocRecipeDetailView.swift` | Изменить | Р6: левая и правая колонки; варианты тулбара (:825-880); перенос `DetailScrollViewProbe` и `formattingBarInset`; публикация `RecipeCommandActions`. |
| `RecipeScalerNative/Views/YDocRecipeDetailColumns.swift` | Создать | Раскладка в две колонки с фиксированной левой колонкой и линией 1 pt (Р6); держит `YDocRecipeDetailView` в разумном размере. |
| `RecipeScalerNative/Views/RecipeDetailActionsMenu.swift` | Изменить | Поповер «Коллекции» на `.padRegular` (:61-62). |
| `RecipeScalerNative/Views/CollectionAssignSheet.swift` | Изменить | Размер содержимого в поповере (300 pt); сохранение при закрытии не меняется (:112-114). |
| `RecipeScalerNative/Views/AssistantSheet.swift` | Изменить | Принимает `session: AssistantSessionModel` вместо собственного `@State` сессии (:26-56); `onDisappear` (:185-210) больше не отменяет стрим; режим панели: ×, история поповером (:129, тулбар :1054-1070). |
| `RecipeScalerNative/AppContainer.swift` | Изменить | Владеет `AssistantSessionModel`; сброс сессии при logout и смене `assistantSessionEpoch`. |
| `RecipeScalerNative/Views/ShoppingListView.swift` | Изменить | Ограничение ширины; Вкусвилл только иконкой при < 640 (:704); ✦ на `.padRegular`. |
| `RecipeScalerNative/Views/AccountView.swift` | Изменить | Необязательный `onDone` → «Готово» в тулбаре листа (Р2a; на iPhone `nil`); `pendingRemindersSetup` обрабатывается и при появлении; без строки встряхивания на iPad (:579); `accountAvatar` (:860-871) заменён на `AccountAvatarView` без изменения вида. Ограничение ширины не нужно: в `.padRegular` профиль — лист. |
| `RecipeScalerNative/Views/DiscoverRootView.swift`, `Views/Discover/DiscoverPublicProfileView.swift` | Изменить | Ограничение ширины 720 / 1100; сегменты в строке заголовка на `.padRegular`; ✦. |
| `RecipeScalerNative/Views/ImportRecipeSheet.swift` | Изменить | Form sheet на `.padRegular` (:216), если нужно. |
| `RecipeScalerNative/AccessibilityIdentifiers.swift`, `RecipeScalerNativeUITests/Helpers/Selectors.swift` | Изменить | Идентификаторы сайдбара, футера, колонки списка, кнопки «Список рецептов», панели ассистента; кнопка «Готово» листа профиля. |
| `RecipeScalerNative/Utils/DebugLaunchOptions.swift` | Изменить | Только DEBUG: `-IPadSidebarHidden`, `-IPadListHidden` (с 2026-10-12 — старт с развёрнутым рецептом: «Свернуть», списка нет; сайдбар не прячет), `-DebugWindowWidth <pt>` для матрицы (T049). |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | Новые ключи `ipad.*` (en + ru). |
| `RecipeScalerNative/Utils/ShakeToOpenAssistantPreference.swift` | Изменить | Р9: `isActive(idiom:)`. |
| `RecipeScalerNativeTests/IPadLayoutPolicyTests.swift`, `RecipesSelectionTests.swift`, `IPadShellItemTests.swift`, `AppLayoutModeTests.swift`, `IPadProfileSheetPolicyTests.swift` | Создать | Чистая логика, включая ширину левой колонки (`IPadLayoutPolicyTests/testLeftColumnIsFixedAndKeepsTheSteps`) и правило листа профиля (Р2a). |
| `RecipeScalerNativeTests/AssistantSessionModelTests.swift` | Создать | Р7: черновик и стрим переживают смену view; закрытие, смена эпохи и logout отменяют задачи. |
| `RecipeScalerNativeTests/ShakeToOpenAssistantPreferenceTests.swift` | Изменить | Проверки `isActive(idiom:)` для iPhone и iPad. |
| `RecipeScalerNativeTests/AppShellCoordinatorTests.swift` | Изменить | Тип пути; переходы листа профиля (Р2a); существующие проверки (:119-216) остаются. |
| `RecipeScalerNativeUITests/Specs/IPadShellSpec.swift`, `IPadRecipesSpec.swift`, `IPadAssistantSpec.swift`, `IPadKeyboardSpec.swift` | Создать | UI-тесты только для iPad (`XCTSkipUnless` по idiom). |
| `scripts/resolve-ipad-simulator.sh`, `scripts/verify-ipad-layout.sh` | Создать | iPad-симулятор и проверка раскладки по состояниям прототипа; `#profile/*` — лист в широком окне, вкладка в ½ (T019a). |
| `scripts/capture-app-store-screenshots.sh`, `scripts/validate-app-store-screenshots.sh` | Изменить | iPad 13″. |
| `docs/DECISIONS.md`, `docs/AGENT-WORKFLOW.md`, `docs/PRD.md` | Изменить | Решения, команды для iPad, «только iPhone» в PRD (:26, :544). |

## Downstream consumers

- **SwiftUI views**:
  - **Оболочка:** `AppShellView` и все корни вкладок (`DiscoverRootView`, `RecipeListView`, `ShoppingListView`, `AccountView`), фиктивная вкладка ассистента. `AccountView` на iPad в широком окне — содержимое листа профиля (Р2a); кнопка «Настроить Напоминания» в «Покупках» (`requestRemindersSetup`, `AppShellCoordinator.swift:203-206`) там открывает лист, а не вкладку.
  - **Раздел «Рецепты»:** `CollectionsRootView`, `CollectionFolderView` (тип пути), `YDocRecipeDetailView` и его блоки (`YDocRecipeDetailBlocks`, `YDocRecipeDetailEditMode`, `RecipeDescriptionEditorBlock`, `DescriptionFormattingBar`, `DetailScrollViewProbe`, `AwakeScrollChromeModifier`, `ScreenAwakeStatusBanner`).
  - **Показ:** `RecipeDetailActionsMenu`, `CollectionAssignSheet`, `AssistantSheet`, `AssistantThreadListSheet`, `MobileTimerPanel`, `ImportRecipeSheet`.
  - **Подборки:** `DiscoverPublicProfileView`, `DiscoverRecipeCardGrid`.
  - **Готовка:** `ProcessTableCookingPresenter` (ветки по idiom: `:55-58`, `:63`, `:92`, `:112`, `:120`) — только проверка, без изменений.
- **Cross-process**:
  - `TARGETED_DEVICE_FAMILY` расширений (Share, Action, HomeWidget, TimerLiveActivity, ShareExtensionUI) — `"1,2"` (T004, правило App Review для расширений); UI расширений не меняется. На iPad теперь доступны Share и Action в Safari, виджет и Live Activity таймера на экране блокировки (iPadOS 17+).
  - Часы: `WatchCredentialsBridge` уже проверяет `WCSession.isSupported()` (`RecipeScalerNative/Services/WatchCredentialsBridge.swift:20`, `:47`, `:72`, `:91`).
  - Live Activity: `TimerLiveActivityCoordinator.swift:190` проверяет `areActivitiesEnabled`.
  - App Intents, быстрые действия, Spotlight, Universal Links приходят через `AppShellCoordinator.handleDeepLink` (`:256`) и путь рецептов.
- **Sync boundaries**: N/A — Yjs и серверный контракт не меняются. Создание коллекции — тот же `createFolder`. Профиль для футера — тот же `AccountAPI.fetchProfile` (`AccountAPI.swift:124`, `:131`) через `AccountSettingsViewModel` (`:88-109`).
- **Persisted state**:
  - `UserDefaults`: `shakeToOpenAssistantEnabled` (не меняется; на iPad игнорируется), режим отображения коллекций (на iPad в колонке игнорируется).
  - Ширина левой колонки рецепта не сохраняется (решение 2026-10-13). Ключ `ipad.recipeDetailLeftColumnWidth`, который успел записать перетаскиваемый разделитель на тестовых устройствах, больше не читается.
  - Флаг «список спрятан пользователем» живёт в памяти координатора, не сохраняется. `@SceneStorage` в v1 не вводится.
  - SQLite, SwiftData, App Group, Keychain — N/A.
- **Tests / verify scripts**:
  - Существующие: `AppShellCoordinatorTests` (тип пути), `AppContainerTests`, `AppShellNavigationSpec` (iPhone, селекторы `tab_*` в `Selectors.swift:23-26`, `:92`), `SnapshotTests` (iPhone 13, `:18`, `:40`); `verify-ui-smoke.sh`, `verify-app-shell.sh`, `verify-assistant.sh`, `verify-recipe-collections.sh`, `verify-shopping-list*.sh`, `verify-discover-public.sh`, `verify-account-settings.sh`, `verify-description-editor.sh`, `verify-recipe-import.sh`, `verify-timer-widget.sh`, `lint-composition-root.sh`, `lint-i18n.sh`, `policy-check.sh`, `capture-app-store-screenshots.sh`.
  - Все они остаются на iPhone-симуляторе (`resolve-simulator.sh` выбирает только `iphone`).

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|-------------------|-------------------------|------------------|
| iPhone: оболочка | На iPhone собирается тот же `modernTabView`/`legacyTabView`: нижний таб-бар из 5 вкладок с прежними идентификаторами | `RecipeScalerNativeUITests/AppShellNavigationSpec` (iPhone) + `bash scripts/verify-ui-smoke.sh` |
| iPhone: режим раскладки | При `idiom == .phone` режим всегда `.phone` при любом size class | `RecipeScalerNativeTests/AppLayoutModeTests/testPhoneIdiomIsAlwaysPhone` |
| iPhone: рецепт | Скриншоты рецепта, правки, покупок, профиля, подборок и импорта на iPhone до и после совпадают попиксельно | `bash scripts/verify-ipad-layout.sh --iphone-regression` (T029) |
| iPhone: стек рецептов | Пуш `.folder` → `.recipe`, назад, диплинк дают тот же путь, что раньше | `RecipeScalerNativeTests/AppShellCoordinatorTests` + `RecipesSelectionTests/testPathRoundTrip` |
| iPhone: встряхивание | При включённой настройке встряхивание открывает ассистента | `RecipeScalerNativeTests/ShakeToOpenAssistantPreferenceTests/testPhoneHonorsPreference` |
| iPad: встряхивание | На iPad встряхивание ничего не открывает; строки настройки в профиле нет | `ShakeToOpenAssistantPreferenceTests/testPadIgnoresShake` + `IPadShellSpec/testProfileHasNoShakeRow` |
| iPad: колонки | Колонка списка видна ровно при `content − 321 ≥ 560`; две колонки ровно при `detail ≥ 720`; широкий тулбар ровно при `detail ≥ 600`; на порогах и на 1 pt ниже | `RecipeScalerNativeTests/IPadLayoutPolicyTests` |
| iPad: ширины прототипа | Для 1194/834 × сайдбар × инспектор × ⅔/½/⅓ политика даёт значения из layout.md §Матрица | `IPadLayoutPolicyTests/testPrototypeMatrix` |
| iPad: сайдбар | Сайдбар показывает «Подборки», «Рецепты», «Покупки», коллекции со счётчиками, «Новая коллекция», футер | `RecipeScalerNativeUITests/IPadShellSpec/testSidebarContents` |
| iPad: выбор коллекции | При активном `IPadRecipesSplitView` выбор коллекции открывает её первый рецепт, в колонке — её рецепты; без split — телефонный экран коллекции в стеке (`[.folder(id)]`) | `IPadShellItemTests/testCollectionMapsToRecipesPath` (оба случая) + `RecipesSelectionTests/testSelectingCollectionOpensFirstRecipe` + `IPadRecipesSpec/testCollectionSelection` |
| iPad: смена size class | Открытый рецепт и коллекция сохраняются при переходе regular ↔ compact | `RecipesSelectionTests/testSelectionSurvivesModeSwitch` + `IPadRecipesSpec/testRotationKeepsRecipe` |
| iPad: ассистент | Тап ✦ открывает панель 340 pt справа от `TabView`; вкладка не меняется; при compact — лист с тем же чатом | `IPadShellItemTests/testAssistantDoesNotChangeSelection` + `IPadAssistantSpec` |
| iPad: черновик ассистента | Введённый текст и вложения сохраняются при смене вкладки с открытой панелью и при переходе панель ↔ лист (смена size class); идущий ответ дописывается | `AssistantSessionModelTests` + `IPadAssistantSpec/testTabSwitchKeepsDraft`, `testSizeClassSwitchKeepsChat` |
| iPhone: ассистент | Лист ассистента открывается, отправляет, показывает историю, как раньше; закрытие листа отменяет стрим и сохраняет тред | `bash scripts/verify-assistant.sh` (iPhone) + `AssistantSessionModelTests/testCloseCancelsStream` |
| iPad: тулбары вкладок | У каждой вкладки и у вкладок коллекций тулбар под таб-баром, не под ним; после показа и скрытия сайдбара — тоже | `bash scripts/verify-ipad-layout.sh` (состояния с открытым и закрытым сайдбаром) |
| iPad: коллекция в режиме верхнего бара | При плейсменте `.topBar` выбор коллекции даёт `.tab(.recipes)` + `.folder(id)` в пути, группа «Коллекции» не появляется в верхнем баре; бейджей в верхнем баре нет | `IPadShellItemTests/testCollectionInTopBarMapsToRecipesTab` + `IPadShellSpec/testTopBarHasNoBadges` |
| iPad: compact | В compact `TabSection` не строится: 5 вкладок, как на iPhone, «Ещё» нет | `IPadShellSpec/testCompactHasNoMoreTab` |
| iPad: футер | Публичный профиль с именем → имя; иначе → номер аккаунта; аватар — фото, если есть, иначе `person.circle.fill`, как в `AccountView` на iPhone | `IPadShellSpec/testFooterPrivateShowsAccountId` + `bash scripts/verify-ipad-layout.sh --iphone-regression` (профиль на iPhone не меняется после выноса `AccountAvatarView` и параметра `onDone`) |
| iPad: лист профиля | В `.padRegular` футер, вкладка «Профиль» верхнего бара, «Настроить Напоминания», ⌘4 и `-OpenTab=profile` открывают form sheet «Моё всё» с «Готово»; `selectedTab` не меняется; в сайдбаре нет вкладки «Профиль»; в `.phone` — вкладка | `IPadProfileSheetPolicyTests` + `AppShellCoordinatorTests/testRemindersSetupInRegularPresentsSheet` + `IPadShellItemTests/testProfileInRegularDoesNotChangeSelection` + `IPadShellSpec/testFooterOpensProfileSheet`, `testTopBarProfileOpensSheet`, `testSidebarHasNoProfileTab` |
| iPad: лист профиля при смене size class | compact → regular на вкладке «Профиль» → прежняя вкладка (или «Рецепты») + лист; regular → compact с открытым листом → лист остаётся | `AppShellCoordinatorTests/testWideningOnProfileTabRestoresPreviousAndPresentsSheet`, `testNarrowingKeepsProfileSheet` |
| iPad: колонки рецепта | Левая колонка рецепта 400; правая не уже 320 (панель 720 → левая 399); панель < 720 → одна колонка; строка «КБЖУ на» с выбором базы не выходит за колонку (выбор переносится под заголовок) | `IPadLayoutPolicyTests/testLeftColumnIsFixedAndKeepsTheSteps` + `RecipeNutritionHeaderLayoutTests` + `IPadRecipesSpec/testListAndTwoColumns` |
| iPad: команды | ⌘E, ⌘+, ⌘−, ⌘0, ⇧⌘L, ⇧⌘P, ⌃⌘A, ⌘⌫ (через подтверждение), ⌘1–⌘4, ⌘J, ⌘F, ⌘N, ⇧⌘I, ⇧⌘N срабатывают; без рецепта меню «Рецепт» неактивно | `RecipeScalerNativeUITests/IPadKeyboardSpec` |
| iPad: раскладка по состояниям | Каждое состояние layout.md §Карта состояний снято и сверено по чек-листу | `bash scripts/verify-ipad-layout.sh` + human gate |
| Все новые строки | Есть en и ru | `bash scripts/lint-i18n.sh` |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| Создание коллекции из сайдбара (`syncService.createFolder`) | введённое имя, `syncService` текущей сессии | после `await` флаг `isSaving` сбрасывается в `defer`; алерт уже закрыт | нет (одиночная запись, как `CollectionsRootView.commitNewFolder` :458); single-flight `isSaving` до первого `await` | двойное подтверждение не создаёт две коллекции — ручная проверка + guard |
| Загрузка профиля для футера (`AccountSettingsViewModel` → `AccountAPI.fetchProfile`) | `userId` на момент запроса | `userId == текущий` перед присвоением имени и фото | `.task(id: FooterKey(userId, revision))` футера | смена аккаунта во время загрузки не показывает чужое имя — `IPadShellSpec` + unit-проверка guard |
| Загрузка фото профиля (`AuthAvatarImage`) | URL аватара | URL не изменился | `.task(id: url)` | — (существующий компонент) |
| Обновление футера после закрытия листа профиля (`profileSheetRevision`) | `userId`, номер ревизии | `userId == текущий` перед присвоением | `.task(id: FooterKey(userId, revision))` футера: новая ревизия отменяет прежнюю загрузку | смена «Публичный профиль» в листе → после «Готово» футер показывает новое имя/номер — `IPadShellSpec/testFooterOpensProfileSheet` |
| Выбор «первого рецепта» коллекции | `collectionId` | синхронно из `syncService.collectionIndex`, без `await` | N/A | N/A — нет async side effects |
| Измерение ширины → `IPadLayoutPolicy` | N/A | N/A | N/A | N/A — синхронный пересчёт в `onGeometryChange` |
| Открытие или закрытие панели ассистента, переход лист ↔ панель | `AssistantSessionModel` (общий, из `AppContainer`) | N/A | SwiftUI-презентация; view не владеет задачами | чат не теряется при смене size class — `IPadAssistantSpec/testSizeClassSwitchKeepsChat` |
| Стрим ответа ассистента (`streamTask`, `bootstrapTask`, `externalSendTask`) | `threadId`, `assistantSessionEpoch` на момент старта | `threadId` и эпоха не изменились перед записью сообщения | `AssistantSessionModel`: отмена при явном закрытии, смене эпохи, logout; не при `onDisappear` view | ответ после смены эпохи не попадает в новую сессию — `AssistantSessionModelTests/testEpochChangeDropsStaleStream` |
| Команды меню (`FocusedValue` с замыканиями) | рецепт или сцена, опубликовавшие значение | действие проверяет, что `recipeId` всё ещё открыт | замыкания живут, пока view в фокусе | ⌘E после закрытия рецепта ничего не делает — `IPadKeyboardSpec` |
| Поповер «Коллекции»: сохранение при закрытии (`CollectionAssignSheet.swift:112-114` → :198) | `recipeId` | как сейчас | как сейчас (`onDisappear`) | тап мимо поповера сохраняет выбор — `IPadRecipesSpec/testCollectionsPopoverPersists` |

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | `recipesPath = []`, `selectedTab` по умолчанию (`.recipes`), панель ассистента закрыта, `AssistantSessionModel` сброшена (сообщения, черновик, вложения), флаг «список спрятан» сброшен, `isProfileSheetPresented = false` и `lastNonProfileTab = .recipes` (выход обычно нажимают в листе профиля), профиль футера очищен | `.task` футера отменяется с view; задачи `AssistantSessionModel` отменены | N/A | меню-команды получают `nil` (view ушли) | после повторного входа оболочка в начальном состоянии, футер без имени прошлого аккаунта |
| account switch | как logout | как logout | как logout | как logout | футер показывает номер и аватар нового аккаунта (фото или `person.circle.fill`) |
| stale session / cold start | путь из диплинка (если есть), иначе выбор первого рецепта; лист профиля закрыт (флаг только в памяти) | — | N/A | ориентации `~ipad` из Info.plist | iPad стартует в правильной раскладке для текущей ширины окна, без мигания компактной раскладки |
| reconnect / partial failure | выбор сохраняется | загрузка профиля повторяется по `.task(id:)` | N/A | N/A | футер переходит с номера аккаунта на имя, когда профиль загрузился |
| удалена открытая коллекция или рецепт (с другого устройства) | выбор переходит на «Все рецепты» / следующий рецепт | — | N/A | N/A | пустой панели и упавшего `YDoc` нет — `RecipesSelectionTests/testDeletedSelectionFallsBack` |

## Cross-target contracts

- **Canonical owner**: состояние оболочки и раздела «Рецепты» — `AppShellCoordinator` (`selectedTab`, `recipesPath: [RecipesRoute]`, `isProfileSheetPresented`). Пороги раскладки — `IPadLayoutPolicy`. Режим раскладки — `AppLayoutMode` в environment.
- **Writer/reader targets**: только основное приложение. Расширения, виджеты и часы состояние оболочки не читают.
- **Validator/normalizer**: `RecipesSelection` нормализует путь — не больше одного `.folder` в начале и одного `.recipe` на iPad; на iPhone путь не нормализуется (телефонный стек может быть глубже).
- **Raw literal exceptions**: числа 280/320/340/400/660/720/1100/560/380/300/36 только в `IPadLayoutPolicy` (`IPadLayoutMetrics`); в view — ссылки на константы. Затемнение 0.25 под выездом списка (Р5) и порог 60 pt левого safe area для «сайдбар плавает» (`IPadSidebarControl`) — тоже константы.

## Locale / theme consumers

- SwiftUI environment: новые подписи берутся из `Localizable.xcstrings` через `LocalizedStringKey`; язык меняется в приложении (`Bundle.currentLocalizedString`) — заголовки сайдбара и меню перерисовываются вместе с остальным UI.
- UIKit / notification categories / scheduled content: N/A.
- Widgets / Live Activities / App Intents: N/A.
- Cached or generated assets: N/A — генерируемых изображений нет; аватар — фото профиля через существующий `AuthAvatarImage` или SF Symbol `person.circle.fill`.
- `.system` effective value: темы приложения (`Тёмный режим: Как в системе`) применяются к сайдбару и инспектору системно.
- Меню-бар: названия меню «Рецепт», «Вид» — ключи `ipad.menu.*`; системные «Правка», «Окно», «Справка» локализует система.

## Compatibility / migration

- Current format/contract: `recipesPath: NavigationPath` → `[RecipesRoute]`. Это смена типа в памяти; путь не сериализуется (`NavigationPath.codable` не используется — проверить в T009), поэтому миграции данных нет.
- Previous supported format: N/A.
- Missing version/default behavior: на iPadOS 17.0–26.1 — старый путь оболочки (Р3). Левая колонка рецепта всегда 400 (на границе 720 — 399), сохранённой ширины нет.
- Unknown future version/ID behavior: коллекция из пути, которой нет в `syncService.folders`, → «Все рецепты» (как удалённая).
- Required legacy fixture tests: сборка и smoke на симуляторе iOS 18.4 (runtime есть локально; нужен iPad-девайс на этом runtime — `xcrun simctl create`), проверка старого пути на iPad (T051).

## Unknown IDs and fallback policy

- DEBUG/CI: неизвестный `AppTab` или `IPadShellItem` в привязке, коллекция без папки → `assertionFailure` + лог.
- Release: безопасный выбор — `.tab(.recipes)` и «Все рецепты», структурированный лог.
- Legacy aliases: N/A.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|----------|----------|---------------|----------------|---------------------------------|
| `UIDeviceFamily` в Info.plist приложения | `TARGETED_DEVICE_FAMILY` в `project.pbxproj` | сборка | `RecipeScalerNative.app/Info.plist` | `plutil -extract UIDeviceFamily json -o - <app>/Info.plist` → `[1,2]` (T003) |
| `UIDeviceFamily` расширений и фреймворков | то же для расширений (Share, Action, HomeWidget, TimerLiveActivity: `"1,2"`), ShareExtensionUI (`"1,2"`) и RecipeScalerCore (`"1,2,4"`) | сборка | `PlugIns/*.appex/Info.plist`, `Frameworks/*.framework/Info.plist` | `[1,2]` у всех четырёх `.appex`, ShareExtensionUI и Core в iOS-приложении; `[4]` у часов и их Core. T004, Release-архив 2026-10-15. Основание — правило App Review из App Extension Programming Guide: расширение должно быть «iPhone/iPad» при любом семействе приложения |
| iPad-скриншоты App Store | `scripts/capture-app-store-screenshots.sh` | симулятор iPad 13″ | каталог скриншотов скрипта | `scripts/validate-app-store-screenshots.sh` проверяет размеры iPad |

## Human gates

- [ ] Прототип как эталон раскладки (вместо Figma): человек просмотрел `layout.md` и подтвердил карту состояний.
- [ ] `layout-audit.json` — не делается: эталон не Figma (решение постановки).
- [ ] Ревью плана человеком до T005. Ответы на Q1–Q6 получены 2026-10-12 (spec.md §Clarifications); осталось одобрить план целиком.
- [ ] Ручной проход на iPad-симуляторе по layout.md §Матрица приёмки после каждой истории; Split View, Slide Over и Stage Manager — вручную.
- [ ] Валидация архива с семейством устройств «1,2» в App Store Connect (T004) — пройдёт при загрузке сборки 1.0.13. Локальный архив собран, `UIDeviceFamily` проверен.
- [ ] Загрузка iPad-скриншотов и выбор в ASC доступности на Mac («Designed for iPad») и Vision Pro — по умолчанию выключить.
- [ ] Отдельный review-агент (T057); self-review не заменяет.

## Verification

- `python3 scripts/verify-plan-policy.py specs/081-ipad-adaptation/plan.md` → `PASS`.
- `SPECIFY_FEATURE_DIRECTORY=specs/081-ipad-adaptation bash scripts/verify-plan-state.sh` → `PLAN STATE: specs/081-ipad-adaptation`.
- **Сборка на iPhone** (каждая фаза):

  ```sh
  SIM_ID="$(bash scripts/resolve-simulator.sh)"
  xcodebuild -scheme RecipeScalerNative -destination "platform=iOS Simulator,id=$SIM_ID" build
  ```

  Ожидается `BUILD SUCCEEDED`.
- **Сборка на iPad:**

  ```sh
  IPAD_ID="$(bash scripts/resolve-ipad-simulator.sh)"
  xcodebuild -scheme RecipeScalerNative -destination "platform=iOS Simulator,id=$IPAD_ID" build
  ```

  Ожидается `BUILD SUCCEEDED`. Локально есть iPad Pro 11-inch (M4) на iOS 26.3.
- **Unit-тесты:** `bash scripts/test-fast.sh` → exit 0, включая `AssistantSessionModelTests`, `IPadLayoutPolicyTests`, `RecipesSelectionTests`, `IPadShellItemTests`, `AppLayoutModeTests`, `IPadProfileSheetPolicyTests`, `AppShellCoordinatorTests`, `ShakeToOpenAssistantPreferenceTests`.
- **iPhone-регрессия** (паттерн `docs/AGENT-WORKFLOW.md:48-55`):

  ```sh
  SIM_ID="$(bash scripts/resolve-simulator.sh)"
  xcodebuild build-for-testing -scheme RecipeScalerNative -destination "platform=iOS Simulator,id=$SIM_ID"
  xcodebuild test-without-building -scheme RecipeScalerNative -destination "platform=iOS Simulator,id=$SIM_ID" \
    -only-testing:RecipeScalerNativeUITests/AppShellNavigationSpec
  SKIP_BUILD=1 bash scripts/verify-ui-smoke.sh
  bash scripts/verify-ipad-layout.sh --iphone-regression
  ```

  Ожидается: `TEST BUILD SUCCEEDED`, `** TEST EXECUTE SUCCEEDED **`, exit 0, 0 отличий.
- **iPad UI-тесты:**

  ```sh
  IPAD_ID="$(bash scripts/resolve-ipad-simulator.sh)"
  xcodebuild build-for-testing -scheme RecipeScalerNative -destination "platform=iOS Simulator,id=$IPAD_ID"
  xcodebuild -scheme RecipeScalerNative -destination "platform=iOS Simulator,id=$IPAD_ID" test-without-building \
    -only-testing:RecipeScalerNativeUITests/IPadShellSpec \
    -only-testing:RecipeScalerNativeUITests/IPadRecipesSpec \
    -only-testing:RecipeScalerNativeUITests/IPadAssistantSpec \
    -only-testing:RecipeScalerNativeUITests/IPadKeyboardSpec
  ```

  Ожидается exit 0.
- **Раскладка по состояниям:** `bash scripts/verify-ipad-layout.sh` → exit 0 и скриншоты `tmp/ipad-verify/<step>-<state>-<orient>-<window>.png` для ручной сверки с прототипом.
- **Без регрессий:** `bash scripts/lint-i18n.sh`, `bash scripts/policy-check.sh`, `bash scripts/lint-composition-root.sh` → exit 0.
- **Перед выпуском:** `bash scripts/verify-all.sh` → exit 0.
- **Семейство устройств:** `plutil -extract UIDeviceFamily json -o - <DerivedData>/…/RecipeScalerNative.app/Info.plist` → `[1,2]`.

## Rollback / maintenance

- **Как откатить:**
  - Быстро — вернуть `TARGETED_DEVICE_FAMILY = 1`: iPad снова получает режим совместимости, iPad-ветки не выполняются, потому что `AppLayoutMode` никогда не станет `.padRegular` (на iPhone-сборке idiom `.phone`, а в режиме совместимости iPad сообщает idiom `.phone`).
  - Полный откат — revert ветки. Переход на `[RecipesRoute]` можно оставить: он не меняет поведение. `AssistantSessionModel` тоже можно оставить: на iPhone лист работает так же.
  - `IPadSidebarControl` — единственная точка UIKit-обхода; если новая iPadOS его сломает, его можно выключить (ничего не делать), потеряв только авто-скрытие сайдбара и ⌃⌘S.
- **Что будет взаимодействовать с изменением в будущем:**
  - любые новые вкладки (`AppTab`) — их нужно добавить и в `AppShellTabRoots`, и в `IPadShellItem`; новые программные переходы к профилю идут через `selectedTab = .profile` — нормализация Р2a превратит их в лист;
  - новые блоки рецепта — решить, в какую колонку;
  - новые листы — решить, поповер или form sheet на iPad;
  - Mac Catalyst или «Designed for iPad»;
  - будущая спека с «ассистент видит рецепт» и сеткой авторов;
  - сайдбар на iPadOS 18+ (Q1, низкий приоритет) — третий построитель таб-бара (Р3).
- **Временные allowlist/quarantine:** DEBUG-флаги `-DebugWindowWidth`, `-IPadSidebarHidden`, `-IPadListHidden` (старт с развёрнутым рецептом) — owner: эта фича; только `#if DEBUG`; убираются, если появится штатный способ задавать ширину окна симулятора из UI-тестов.
