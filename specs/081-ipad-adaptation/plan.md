# План: iPad-адаптация — адаптивная оболочка, колонки рецептов, ассистент-инспектор

**Дата**: 2026-10-12  
**Спека**: [spec.md](./spec.md)  
**Раскладка**: [layout.md](./layout.md)  
**Задачи**: [tasks.md](./tasks.md)

## Границы

- **В scope**:
  - `TARGETED_DEVICE_FAMILY = "1,2"` для таргета `RecipeScalerNative`.
  - iPad-оболочка на `TabView(.sidebarAdaptable)` (iPadOS 26.2+): сайдбар, раздел «Коллекции», футер профиля, верхний и нижний таб-бары.
  - Раздел «Рецепты»: колонка списка и панель рецепта, рецепт в две колонки с перетаскиваемым разделителем (ширина сохраняется, Q5).
  - Ассистент как `.inspector`.
  - Поповеры «Коллекции», истории чатов и таймеров.
  - Правка в две колонки.
  - Ограничение ширины у «Покупок», «Профиля», «Подборок»; импорт в form sheet.
  - Отключение встряхивания на iPad.
  - `.commands` и `keyboardShortcut`.
  - Многозадачность в одном окне.
  - Поиск iPad-симулятора и проверочный скрипт iPad-раскладки; iPad-скриншоты App Store.
- **Вне scope**:
  - Mac и Vision Pro.
  - iPad-раскладка расширений, виджетов, Live Activity и часов.
  - Изменение логики поиска, CRDT, сервера и веба.
  - Экспорт в PDF (Q3), откат правок в режиме правки (Q2), сгенерированный аватар (Q6): этого нет на iPhone.
  - Сайдбар на iPadOS 18.0–26.1 (Q1): низкий приоритет, на потом (Р3).
  - Несколько окон (Q4: только если спайк S7 покажет, что дёшево; иначе STOP 5).
  - Идеи на потом из спеки: ассистент «видит» рецепт; сетка карточек авторов.
- **STOP conditions** (остановиться, записать в `docs/DECISIONS.md`, спросить человека):
  1. **iPhone.** Любое расхождение на iPhone: красный `verify-ui-smoke.sh`, `AppShellNavigationSpec` или unit-тесты; отличие iPhone-скриншотов до и после (T029) — кроме осознанной правки `[RecipesRoute]`, которая не меняет пиксели.
  2. **Белый экран или некликабельный UI на iPad-симуляторе** (повтор `docs/DECISIONS.md:411`) после спайка T005/T006. Сначала — минимальная репродукция в спайке, а не обход в продакшен-коде.
  3. **Вложенная навигация.** И вариант A (`NavigationSplitView` внутри `Tab`), и вариант B (два `NavigationStack` в `HStack`) ломают панели инструментов, `.searchable` или переходы.
  4. **Коллекции в сайдбаре.** `TabSection` с динамическими коллекциями не работает без дублирования стека рецептов на каждую коллекцию (утечки, двойная подписка на YDoc). Тогда коллекции переезжают в меню заголовка колонки списка, а сайдбар остаётся без раздела — это отклонение от прототипа, нужно решение человека.
  5. **Несколько окон** требуют переноса `AppShellCoordinator` из общего `AppContainer` (`RecipeScalerNativeApp.swift:121`, `AppContainer.swift:65`) в отдельную сцену. По умолчанию это STOP для мультиоконности (Q4); одно окно с изменяемым размером остаётся в scope.
  6. **Устаревшие API.** Нужный API есть только в beta-SDK или требует поднять минимальную iOS выше 17.0.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | Документы, схема Yjs и запись не меняются. Новая коллекция из сайдбара идёт через существующий `syncService.createFolder(name:)` (`CollectionsRootView.swift:475`). Правки рецепта — те же телефонные компоненты. |
| Web parity | N/A | Только нативная раскладка; веб не меняется. Аватар — телефонный (фото или `person.circle.fill`), нового рисования аватара нет (Q6). |
| Offline-first | PASS | Колонки, инспектор и поповеры работают на локальных данных. Футер профиля офлайн показывает номер аккаунта и `person.circle.fill` (FR-004). Ширина левой колонки рецепта хранится локально (`UserDefaults`). Сетевые действия (импорт, Вкусвилл) отключаются, как на iPhone. |
| Native UI | PASS | `TabView(.sidebarAdaptable)`, `Tab`/`TabSection`, `.inspector`, `.popover`, `.presentationSizing(.form)`, `.commands`, `keyboardShortcut`, `NavigationSplitView` или `NavigationStack`. Шрифт Martian через `AppTypography`. |
| Phased delivery | PASS | 7 историй, каждая выпускается отдельно (spec.md); US1 — минимальный выпуск. Сначала спайк, вёрстка после него. |
| i18n | PASS | Новые строки — ключи в `Localizable.xcstrings` (en + ru), телефонные ключи переиспользуются (FR-032); `bash scripts/lint-i18n.sh`. |
| Documentation | PASS | spec.md, plan.md, tasks.md, layout.md; записи в `docs/DECISIONS.md` (оболочка, старый путь, окна) и `docs/AGENT-WORKFLOW.md` (iPad-симулятор) — T054. |

## Очерёдность

1. **Setup (T001–T004).** Скрипты iPad-симулятора, семейство устройств, проверка расширений. Без них нечем проверять.
2. **Foundational (T005–T011).**
   - Спайк оболочки и контента на живом iPad-симуляторе. Первым — из-за `DECISIONS.md:411`.
   - Чистая политика раскладки, режим раскладки в environment, типизированный путь рецептов, адаптивные модификаторы показа.
   - Всё остальное зависит от этого шага.
3. **US1 (T012–T022)** — оболочка. Без неё нет iPad-выпуска.
4. **US2 (T023–T031)** — колонки рецептов. Зависит от T008–T010 и решения спайка по варианту A/B.
5. **US3 (T032–T035)**, **US4 (T036–T040)**, **US5 (T041–T044)** — независимы друг от друга, все после US2: им нужна панель рецепта и правило ширины.
6. **US6 (T045–T048)** — меню и клавиатура. Публикует действия из US1–US5, поэтому после них.
7. **US7 (T049–T052)** — матрица многозадачности и решение по окнам.
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
- «Профиль» и «Ассистент» с `.defaultVisibility(.hidden, for: .sidebar)`.
- `TabSection("collections.title")`: по `Tab` на каждую коллекцию, `.defaultVisibility(.hidden, for: .tabBar)`, `.sectionActions` с «Новая коллекция».
- `.tabViewSidebarBottomBar` — футер профиля.
- Тот же `MobileTimerAccessoryModifier` (`:1029-1043`).

Содержимое вкладок — те же корневые view, что в `modernTabBar` (`:709-770`). Общие построители выносятся из `AppShellView` в `AppShellTabRoots`, чтобы не копировать.

Выбор хранит `IPadShellItem`:

```swift
enum IPadShellItem: Hashable {
    case tab(AppTab)
    case collection(String)
}
```

Это вычисляемая привязка поверх `coordinator.selectedTab` и `coordinator.recipesPath`, второго источника правды нет:

- **Чтение:** если `selectedTab == .recipes` и в пути есть `.folder(id)` пользовательской коллекции — `.collection(id)`; иначе `.tab(selectedTab)`.
- **Запись `.collection(id)`** зависит от режима. Привязка получает `isSplitActive`: `true`, только когда раздел «Рецепты» рисует `IPadRecipesSplitView` (`.padRegular`, после T024); в US1, в compact и на телефонном стеке — `false`.
  - `isSplitActive == false`: `selectedTab = .recipes`, путь = `[.folder(id)]` — телефонный экран коллекции в стеке (spec.md US1, сценарий 5).
  - `isSplitActive == true`: `selectedTab = .recipes`, путь = `[.folder(id), .recipe(recipeId: первый рецепт коллекции, folderContext: id)]` — колонка коллекции и её первый рецепт (US2, сценарий 5). Пустая коллекция — `[.folder(id)]`.
  - Оба случая — `IPadShellItemTests/testCollectionMapsToRecipesPath`.
- **Запись `.tab(.assistant)`:** выбор не меняется, ассистент открывается или закрывается — как `handleTabSelection` (`AppShellCoordinator.swift:147`).

Содержимое невыбранных `Tab` коллекций — пустое (`Color.clear`), чтобы не держать несколько стеков рецептов (STOP 4).

### Р3. Старый путь (iPadOS 17.0–26.1) — решено (Q1)

Оболочка не меняется: `legacyTabView` с `.tabItem`. Система сама рисует верхний таб-бар на iPadOS 18+ и нижний на 17. Сайдбара, раздела «Коллекции» и футера нет; коллекции доступны телефонным экраном.

Колонки рецепта, политика ширины, инспектор (`.inspector` есть с iOS 17), поповеры, form sheet и ограничение ширины работают везде, где `AppLayoutMode == .padRegular`. Капсулы таймеров нет — как на старом пути iPhone.

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

Вариант выбирает спайк T006. Обе схемы используют одну политику и одно состояние.

- **A (предпочтительный):** `NavigationSplitView` из двух колонок внутри `Tab`.
  - Колонка списка `.navigationSplitViewColumnWidth(320)`.
  - `columnVisibility` и стиль (`.balanced`, если список помещается; `.prominentDetail` с выездом списка поверх рецепта, если нет) задаёт `IPadLayoutPolicy`.
  - Кнопку «Список рецептов» даёт система.
- **B (запасной):** `HStack` из двух `NavigationStack` — список 320 pt, разделитель 1 pt, панель рецепта. Кнопка «Список рецептов» — своя (`ToolbarItem(placement: .topBarLeading)`, `sidebar.left`), список поверх — `.overlay` с затемнением.

Колонка списка — `RecipeListView` в «режиме колонки»: тот же список, поиск, меню «+». Строки выбирают рецепт (`Button` и выделение) вместо `NavigationLink(value:)` (`RecipeListView.swift:535`) только при `.padRegular`. Плитка папок (`viewModeMenu`, `:403-435`) в колонке не показывается.

Панель рецепта — `YDocRecipeDetailView(recipeId:)` с `.id(recipeId)` в корне своего стека.

### Р6. Рецепт в две колонки

Тело `YDocRecipeDetailView` (`YDocRecipeDetailView.swift:274-414`) раскладывается на два `@ViewBuilder`:

- **левая колонка:** `RecipeDetailImageSection` (:280), заголовок или `editHeader` (:301-310), `servingsBlock` (:312), `YDocIngredientsEditSection` (:317) / `YDocIngredientsSection` (:374), `nutritionBlock` (:392-396);
- **правая колонка:** `RecipeDescriptionEditorBlock` (:400) / `StepsSection` (:414).

Одна колонка — `VStack` в прежнем порядке с прежними отступами: на iPhone дерево view эквивалентно текущему.

Две колонки (`.padRegular` и панель ≥ 720) — `HStack(spacing: 0)` из двух `ScrollView`:

- левая — ширина `IPadLayoutPolicy.detailLeftWidth(preferred:detailWidth:)`: по умолчанию 400, от 320 до 480, правой остаётся не меньше 320;
- перетаскиваемый разделитель (см. ниже);
- правая с `frame(maxWidth: 660)` и отступами 32;
- общий `ScrollViewReader` над обеими колонками.

**Разделитель (Q5, FR-012a)** — как в Apple Notes:

- линия 1 pt (`Divider`), область захвата 12 pt по центру линии;
- `DragGesture` меняет живую ширину в `@State`, каждое значение проходит через `detailLeftWidth` (упоры 320 и 480, правой ≥ 320);
- при отпускании действующая ширина пишется в `@AppStorage("ipad.recipeDetailLeftColumnWidth")` — одно значение на устройство, общее для просмотра и правки;
- при раскладке сохранённое значение только читается и ужимается под текущую панель; ширина окна, список и инспектор его не перезаписывают;
- отдельного порога нет: две колонки по-прежнему при панели ≥ 720, а 320 + 1 + 320 = 641 < 720, поэтому оба минимума всегда помещаются; на самой границе 720 левая колонка не шире 399;
- VoiceOver: элемент «Ширина колонок» с `accessibilityAdjustableAction` (±20 pt); на трекпаде — курсор изменения ширины, если такой API есть на целевой iPadOS (не блокирует).

Переносы в правую колонку:

- `DetailScrollViewProbe` (:277) — для прокрутки без рук (FR-026);
- `formattingBarInset` (`:505-507`, `:776-789`) — через `.safeAreaInset(edge: .bottom)` правого `ScrollView` (FR-028).

`AwakeScrollChromeModifier` (:761) остаётся на внешнем контейнере, поэтому полоса готовки тянется на обе колонки (FR-023). `.mobileTimerPanelBottomPadding` действует на обе колонки.

### Р7. Показ: инспектор, поповеры, form sheet

- **Ассистент.** Один `showAssistant` (`AppShellView.swift:106`), два показа:
  - `.inspector(isPresented: mode == .padRegular ? $showAssistant : .constant(false))` + `.inspectorColumnWidth(340)` на уровне `TabView`;
  - существующий `AssistantSheetModifier` (`:1046-1072`) получает `isPresented: mode == .padRegular ? .constant(false) : $showAssistant`.

  Внутри инспектора — содержимое `AssistantSheet` без изменений. Если `AssistantPresentation == .inspector`, добавляется ×, а история (`AssistantSheet.swift:129`) показывается поповером с содержимым `AssistantThreadListSheet`.

  Переход size class при открытом ассистенте: лист закрывается, инспектор открывается, и наоборот; чат берётся из `AssistantSessionStore` (проверяется в T006).
- **Поповеры.** `.adaptivePopover(isPresented:...)`: при `.phone` — тот же `.sheet` с той же хромой (`appOpaqueSheetPresentation()`), при `.padRegular` — `.popover`. Применяется к:
  - `CollectionAssignSheet` из «…» (`RecipeDetailActionsMenu.swift:61-62`, поповер 300 pt);
  - истории ассистента;
  - таймерам: тап по капсуле на `.padRegular` открывает поповер 380 pt с `MobileTimerPanel(.insetExpanded)` вместо раскрытой панели (`AppShellView.swift:650-664`).
- **Импорт.** `ImportRecipeSheet` (`ImportRecipeSheet.swift:216`) на `.padRegular` — `.presentationSizing(.form)` (iOS 18+; на iOS 17 iPad сам показывает form sheet). Если окажется, что `detents: [.large]` уже даёт form sheet, правка не нужна (T020).

### Р8. Меню и клавиатура

`.commands` на `WindowGroup` (`RecipeScalerNativeApp.swift:176`). Действия публикуются через `.focusedSceneValue`:

- `AppCommandActions` — из `AppShellView`;
- `RecipeCommandActions` — из `YDocRecipeDetailView`.

Публикация идёт только при `idiom == .pad`. На iPhone значения `nil`, команды неактивны, поведение не меняется. Таблица команд — layout.md §Меню; в меню только действия, которые есть на iPhone («Экспорт в PDF…» не делается, Q3). ⌘F — `.searchFocused` (iOS 18+); на iOS 17 команды «Найти» нет.

### Р9. Встряхивание

`ShakeToOpenAssistantPreference` получает чистую проверку `isActive(idiom:)` = `isEnabled && idiom != .pad`. `handleDeviceShake` (`AppShellView.swift:214`) и обработчик запроса на встряхивание (`:205`) используют её вместо `isEnabled`. Строку `AccountView.swift:579-585` на iPad не показываем. Ключ `shakeToOpenAssistantEnabled` (`ShakeToOpenAssistantPreference.swift:11`) не трогаем.

### Ловушка iOS 26: environment-observable в тулбаре

В тулбарах и аксессуарах нельзя читать `@Environment(SomeObservable.self)`: это ловушка iOS 26, описанная в `ShoppingListView.swift:26-27` и `RecipeDetailShareButton.swift:15-16`. Зависимости передаются явно — это касается новых кнопок ✦, футера сайдбара и `sectionActions`.

### Результаты спайка (T005 — S1, S2, S3, S7; T006 — S4, S5, S6)

| # | Вопрос | Вердикт | Решение |
|---|--------|---------|---------|
| S1 | `.sidebarAdaptable` + `TabSection` с динамическими коллекциями + `.sectionActions` + `.tabViewSidebarBottomBar` на iPad-симуляторе 26.x: нет белого экрана, всё кликается | — | — |
| S2 | Можно ли читать и менять видимость сайдбара (⌃⌘S, свернуть в правке, меню заголовка списка только при скрытом сайдбаре) | — | если нет: меню заголовка показывается всегда, сайдбар в правке не сворачивается, ⌃⌘S — системный пункт |
| S3 | В узком окне `.sidebarAdaptable` даёт нижний таб-бар, как `modernTabView` на iPhone (минимизация, аксессуар таймеров) | — | если нет: в compact рисуем `modernTabView` |
| S4 | Вариант A (`NavigationSplitView` в `Tab`) или B (`HStack` из двух стеков): тулбары колонок, `.searchable`, `.prominentDetail` поверх | — | — |
| S5 | `.inspector` на уровне `TabView`: ширина 340, открыт поверх смены вкладок, переход sheet ↔ inspector при смене size class | — | — |
| S6 | `.popover` от `Menu` («…») и от `tabViewBottomAccessory`; где капсула таймеров в режиме сайдбара | — | если аксессуара в режиме сайдбара нет: своя капсула `.overlay(alignment: .bottom)` |
| S7 | Сколько стоит несколько окон (общий `AppContainer`) | — | по умолчанию STOP 5 |

Вердикты: CHECKED / VERIFIED / INCONCLUSIVE / FAILED.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative.xcodeproj/project.pbxproj` | Изменить | `TARGETED_DEVICE_FAMILY = "1,2"` для приложения (:4158, :4397, :4419, :4442); расширения — по итогам T004; регистрация новых файлов. |
| `RecipeScalerNative/Info.plist` | Проверить, не менять | Ориентации `~ipad` уже есть (:116-122). `UIApplicationSupportsMultipleScenes` не добавляем (STOP 5). |
| `RecipeScalerNative/Views/IPad/AppLayoutMode.swift` | Создать | Р1: режим раскладки, ключ environment, вычисление из idiom и size class. |
| `RecipeScalerNative/Views/IPad/IPadLayoutPolicy.swift` | Создать | Константы и чистая политика колонок, включая ширину левой колонки рецепта (layout.md §Токены). |
| `RecipeScalerNative/Views/IPad/AdaptivePresentation.swift` | Создать | `.adaptivePopover`, `.iPadReadableWidth(_:)`, `.iPadFormSheet()` — без эффекта при `.phone`. |
| `RecipeScalerNative/Views/IPad/IPadShellItem.swift` | Создать | Р2: выбор оболочки и вычисляемая привязка. |
| `RecipeScalerNative/Views/IPad/IPadAdaptiveTabView.swift` | Создать | Р2: `TabView(.sidebarAdaptable)`. |
| `RecipeScalerNative/Views/IPad/IPadSidebarProfileFooter.swift` | Создать | Футер профиля (FR-004). |
| `RecipeScalerNative/Views/AccountAvatarView.swift` | Создать | Телефонный аватар (фото или `person.circle.fill`), вынесенный из `AccountView` (:860-871) без изменения вида; используется в `AccountView` и футере сайдбара (FR-005). |
| `RecipeScalerNative/Views/IPad/IPadRecipesSplitView.swift` | Создать | Р5: колонки раздела «Рецепты». |
| `RecipeScalerNative/Views/IPad/IPadAssistantToolbarButton.swift` | Создать | Кнопка ✦ для `.padRegular`. |
| `RecipeScalerNative/Views/IPad/IPadCommands.swift` | Создать | Р8: `FocusedValueKey`, `AppCommandActions`, `RecipeCommandActions`, `Commands`. |
| `RecipeScalerNative/Views/AppShellTabRoots.swift` | Создать | Общие корни вкладок для `modernTabBar` и `IPadAdaptiveTabView`. |
| `RecipeScalerNative/Routing/RecipesSelection.swift` | Создать | Р4: чистые функции путь ↔ выбор. |
| `RecipeScalerNative/Routing/AppShellCoordinator.swift` | Изменить | `recipesPath: [RecipesRoute]` (:68); помощники выбора; хранение флага «список спрятан». |
| `RecipeScalerNative/Views/AppShellView.swift` | Изменить | Ветка iPad в `tabView` (:690-697); инспектор (:426); защита от встряхивания (:214); тап по капсуле таймеров (:650-664); публикация команд. |
| `RecipeScalerNative/ContentView.swift` | Изменить | Режим раскладки в `rootChrome` (:192-210). |
| `RecipeScalerNative/RecipeScalerNativeApp.swift` | Изменить | `.commands` на `WindowGroup` (:176). |
| `RecipeScalerNative/Views/RecipeListView.swift` | Изменить | `Binding<[RecipesRoute]>` (:18, :40); режим колонки (выбор вместо push, :535); контекстное меню (iPad) на тех же обработчиках, что свайпы (:544-573). |
| `RecipeScalerNative/Views/CollectionsRootView.swift`, `CollectionFolderView.swift` | Изменить | Тип привязки пути; создание коллекции вынесено в общий помощник (`commitNewFolder` :458) для сайдбара. |
| `RecipeScalerNative/Views/YDocRecipeDetailView.swift` | Изменить | Р6: левая и правая колонки; варианты тулбара (:825-880); перенос `DetailScrollViewProbe` и `formattingBarInset`; публикация `RecipeCommandActions`. |
| `RecipeScalerNative/Views/YDocRecipeDetailColumns.swift` | Создать | Раскладка в две колонки и перетаскиваемый разделитель с сохранением ширины (Р6); держит `YDocRecipeDetailView` в разумном размере. |
| `RecipeScalerNative/Views/RecipeDetailActionsMenu.swift` | Изменить | Поповер «Коллекции» на `.padRegular` (:61-62). |
| `RecipeScalerNative/Views/CollectionAssignSheet.swift` | Изменить | Размер содержимого в поповере (300 pt); сохранение при закрытии не меняется (:112-114). |
| `RecipeScalerNative/Views/AssistantSheet.swift` | Изменить | Режим инспектора: ×, история поповером (:129, тулбар :1054-1070). |
| `RecipeScalerNative/Views/ShoppingListView.swift` | Изменить | Ограничение ширины; Вкусвилл только иконкой при < 640 (:704); ✦ на `.padRegular`. |
| `RecipeScalerNative/Views/AccountView.swift` | Изменить | Ограничение ширины; без строки встряхивания на iPad (:579); `accountAvatar` (:860-871) заменён на `AccountAvatarView` без изменения вида. |
| `RecipeScalerNative/Views/DiscoverRootView.swift`, `Views/Discover/DiscoverPublicProfileView.swift` | Изменить | Ограничение ширины 720 / 1100; сегменты в строке заголовка на `.padRegular`; ✦. |
| `RecipeScalerNative/Views/ImportRecipeSheet.swift` | Изменить | Form sheet на `.padRegular` (:216), если нужно. |
| `RecipeScalerNative/AccessibilityIdentifiers.swift`, `RecipeScalerNativeUITests/Helpers/Selectors.swift` | Изменить | Идентификаторы сайдбара, футера, колонки списка, инспектора. |
| `RecipeScalerNative/Utils/DebugLaunchOptions.swift` | Изменить | Только DEBUG: `-IPadSidebarHidden`, `-IPadListHidden`, `-DebugWindowWidth <pt>` для матрицы (T049). |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | Новые ключи `ipad.*` (en + ru). |
| `RecipeScalerNative/Utils/ShakeToOpenAssistantPreference.swift` | Изменить | Р9: `isActive(idiom:)`. |
| `RecipeScalerNativeTests/IPadLayoutPolicyTests.swift`, `RecipesSelectionTests.swift`, `IPadShellItemTests.swift`, `AppLayoutModeTests.swift` | Создать | Чистая логика, включая clamp ширины левой колонки (`IPadLayoutPolicyTests/testLeftColumnClamp`). |
| `RecipeScalerNativeTests/ShakeToOpenAssistantPreferenceTests.swift` | Изменить | Проверки `isActive(idiom:)` для iPhone и iPad. |
| `RecipeScalerNativeTests/AppShellCoordinatorTests.swift` | Изменить при необходимости | Тип пути; существующие проверки (:119-216) остаются. |
| `RecipeScalerNativeUITests/Specs/IPadShellSpec.swift`, `IPadRecipesSpec.swift`, `IPadAssistantSpec.swift`, `IPadKeyboardSpec.swift` | Создать | UI-тесты только для iPad (`XCTSkipUnless` по idiom). |
| `scripts/resolve-ipad-simulator.sh`, `scripts/verify-ipad-layout.sh` | Создать | iPad-симулятор и проверка раскладки по состояниям прототипа. |
| `scripts/capture-app-store-screenshots.sh`, `scripts/validate-app-store-screenshots.sh` | Изменить | iPad 13″. |
| `docs/DECISIONS.md`, `docs/AGENT-WORKFLOW.md`, `docs/PRD.md` | Изменить | Решения, команды для iPad, «только iPhone» в PRD (:26, :544). |

## Downstream consumers

- **SwiftUI views**:
  - **Оболочка:** `AppShellView` и все корни вкладок (`DiscoverRootView`, `RecipeListView`, `ShoppingListView`, `AccountView`), фиктивная вкладка ассистента.
  - **Раздел «Рецепты»:** `CollectionsRootView`, `CollectionFolderView` (тип пути), `YDocRecipeDetailView` и его блоки (`YDocRecipeDetailBlocks`, `YDocRecipeDetailEditMode`, `RecipeDescriptionEditorBlock`, `DescriptionFormattingBar`, `DetailScrollViewProbe`, `AwakeScrollChromeModifier`, `ScreenAwakeStatusBanner`).
  - **Показ:** `RecipeDetailActionsMenu`, `CollectionAssignSheet`, `AssistantSheet`, `AssistantThreadListSheet`, `MobileTimerPanel`, `ImportRecipeSheet`.
  - **Подборки:** `DiscoverPublicProfileView`, `DiscoverRecipeCardGrid`.
  - **Готовка:** `ProcessTableCookingPresenter` (ветки по idiom: `:55-58`, `:63`, `:92`, `:112`, `:120`) — только проверка, без изменений.
- **Cross-process**:
  - `TARGETED_DEVICE_FAMILY` расширений (Share, Action, HomeWidget, TimerLiveActivity, ShareExtensionUI) — только если проверка архива T004 этого потребует; UI расширений не меняется.
  - Часы: `WatchCredentialsBridge` уже проверяет `WCSession.isSupported()` (`RecipeScalerNative/Services/WatchCredentialsBridge.swift:20`, `:47`, `:72`, `:91`).
  - Live Activity: `TimerLiveActivityCoordinator.swift:190` проверяет `areActivitiesEnabled`.
  - App Intents, быстрые действия, Spotlight, Universal Links приходят через `AppShellCoordinator.handleDeepLink` (`:256`) и путь рецептов.
- **Sync boundaries**: N/A — Yjs и серверный контракт не меняются. Создание коллекции — тот же `createFolder`. Профиль для футера — тот же `AccountAPI.fetchProfile` (`AccountAPI.swift:124`, `:131`) через `AccountSettingsViewModel` (`:88-109`).
- **Persisted state**:
  - `UserDefaults`: `shakeToOpenAssistantEnabled` (не меняется; на iPad игнорируется), режим отображения коллекций (на iPad в колонке игнорируется).
  - `UserDefaults`, новый ключ `ipad.recipeDetailLeftColumnWidth` (Double, pt) — ширина левой колонки рецепта на iPad (Q5). Пишется только при отпускании разделителя, читается с clamp; нет ключа — 400. На iPhone не читается и не пишется. Это настройка устройства, не аккаунта: при выходе не сбрасывается, в синхронизацию не попадает.
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
| iPad: ассистент | Тап ✦ открывает инспектор 340 pt; вкладка не меняется; при compact — лист с тем же чатом | `IPadShellItemTests/testAssistantDoesNotChangeSelection` + `IPadAssistantSpec` |
| iPad: футер | Публичный профиль с именем → имя; иначе → номер аккаунта; аватар — фото, если есть, иначе `person.circle.fill`, как в `AccountView` на iPhone | `IPadShellSpec/testFooterPrivateShowsAccountId` + `bash scripts/verify-ipad-layout.sh --iphone-regression` (профиль на iPhone не меняется после выноса `AccountAvatarView`) |
| iPad: разделитель колонок | Левая колонка рецепта по умолчанию 400, не уже 320 и не шире 480; правая не уже 320 (панель 720 → левая 399); панель < 720 → одна колонка; ширина после перетаскивания переживает перезапуск | `IPadLayoutPolicyTests/testLeftColumnClamp` + `IPadRecipesSpec/testColumnDividerDragPersists` |
| iPad: команды | ⌘E, ⌘+, ⌘−, ⌘0, ⇧⌘L, ⇧⌘P, ⌃⌘A, ⌘⌫ (через подтверждение), ⌘1–⌘4, ⌘J, ⌘F, ⌘N, ⇧⌘I, ⇧⌘N срабатывают; без рецепта меню «Рецепт» неактивно | `RecipeScalerNativeUITests/IPadKeyboardSpec` |
| iPad: раскладка по состояниям | Каждое состояние layout.md §Карта состояний снято и сверено по чек-листу | `bash scripts/verify-ipad-layout.sh` + human gate |
| Все новые строки | Есть en и ru | `bash scripts/lint-i18n.sh` |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| Создание коллекции из сайдбара (`syncService.createFolder`) | введённое имя, `syncService` текущей сессии | после `await` флаг `isSaving` сбрасывается в `defer`; алерт уже закрыт | нет (одиночная запись, как `CollectionsRootView.commitNewFolder` :458); single-flight `isSaving` до первого `await` | двойное подтверждение не создаёт две коллекции — ручная проверка + guard |
| Загрузка профиля для футера (`AccountSettingsViewModel` → `AccountAPI.fetchProfile`) | `userId` на момент запроса | `userId == текущий` перед присвоением имени и фото | `.task(id: userId)` футера | смена аккаунта во время загрузки не показывает чужое имя — `IPadShellSpec` + unit-проверка guard |
| Загрузка фото профиля (`AuthAvatarImage`) | URL аватара | URL не изменился | `.task(id: url)` | — (существующий компонент) |
| Выбор «первого рецепта» коллекции | `collectionId` | синхронно из `syncService.collectionIndex`, без `await` | N/A | N/A — нет async side effects |
| Измерение ширины → `IPadLayoutPolicy` | N/A | N/A | N/A | N/A — синхронный пересчёт в `onGeometryChange` |
| Перетаскивание разделителя → запись ширины | N/A | N/A | жест SwiftUI | N/A — синхронная запись в `UserDefaults` в `onEnded`, без `await` |
| Открытие или закрытие инспектора, переход sheet ↔ inspector | `AssistantSessionStore` (общий) | N/A | SwiftUI-презентация | чат не теряется при смене size class — `IPadAssistantSpec/testSizeClassSwitchKeepsChat` |
| Команды меню (`FocusedValue` с замыканиями) | рецепт или сцена, опубликовавшие значение | действие проверяет, что `recipeId` всё ещё открыт | замыкания живут, пока view в фокусе | ⌘E после закрытия рецепта ничего не делает — `IPadKeyboardSpec` |
| Поповер «Коллекции»: сохранение при закрытии (`CollectionAssignSheet.swift:112-114` → :198) | `recipeId` | как сейчас | как сейчас (`onDisappear`) | тап мимо поповера сохраняет выбор — `IPadRecipesSpec/testCollectionsPopoverPersists` |

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|------------|-----------|---------------|-----------------|---------------------------|-------------------------|
| logout | `recipesPath = []`, `selectedTab` по умолчанию (`.recipes`), инспектор закрыт, флаг «список спрятан» сброшен, профиль футера очищен | `.task` футера отменяется с view | `ipad.recipeDetailLeftColumnWidth` остаётся: настройка устройства, не аккаунта | меню-команды получают `nil` (view ушли) | после повторного входа оболочка в начальном состоянии, футер без имени прошлого аккаунта |
| account switch | как logout | как logout | как logout | как logout | футер показывает номер и аватар нового аккаунта (фото или `person.circle.fill`) |
| stale session / cold start | путь из диплинка (если есть), иначе выбор первого рецепта | — | N/A | ориентации `~ipad` из Info.plist | iPad стартует в правильной раскладке для текущей ширины окна, без мигания компактной раскладки |
| reconnect / partial failure | выбор сохраняется | загрузка профиля повторяется по `.task(id:)` | N/A | N/A | футер переходит с номера аккаунта на имя, когда профиль загрузился |
| удалена открытая коллекция или рецепт (с другого устройства) | выбор переходит на «Все рецепты» / следующий рецепт | — | N/A | N/A | пустой панели и упавшего `YDoc` нет — `RecipesSelectionTests/testDeletedSelectionFallsBack` |

## Cross-target contracts

- **Canonical owner**: состояние оболочки и раздела «Рецепты» — `AppShellCoordinator` (`selectedTab`, `recipesPath: [RecipesRoute]`). Пороги раскладки — `IPadLayoutPolicy`. Режим раскладки — `AppLayoutMode` в environment.
- **Writer/reader targets**: только основное приложение. Расширения, виджеты и часы состояние оболочки не читают.
- **Validator/normalizer**: `RecipesSelection` нормализует путь — не больше одного `.folder` в начале и одного `.recipe` на iPad; на iPhone путь не нормализуется (телефонный стек может быть глубже).
- **Raw literal exceptions**: числа 280/320/340/400/480/660/720/1100/560/380/300/36/12 только в `IPadLayoutPolicy` (`IPadLayoutMetrics`); в view — ссылки на константы.

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
- Missing version/default behavior: на iPadOS 17.0–26.1 — старый путь оболочки (Р3). Нет сохранённой ширины левой колонки → 400; сохранённая вне 320–480 → clamp при чтении.
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
| `UIDeviceFamily` расширений | то же для расширений | сборка | `PlugIns/*.appex/Info.plist` | по итогам T004: либо `[1]` и валидация архива проходит, либо `[1,2]` |
| iPad-скриншоты App Store | `scripts/capture-app-store-screenshots.sh` | симулятор iPad 13″ | каталог скриншотов скрипта | `scripts/validate-app-store-screenshots.sh` проверяет размеры iPad |

## Human gates

- [ ] Прототип как эталон раскладки (вместо Figma): человек просмотрел `layout.md` и подтвердил карту состояний.
- [ ] `layout-audit.json` — не делается: эталон не Figma (решение постановки).
- [ ] Ревью плана человеком до T005. Ответы на Q1–Q6 получены 2026-10-12 (spec.md §Clarifications); осталось одобрить план целиком.
- [ ] Ручной проход на iPad-симуляторе по layout.md §Матрица приёмки после каждой истории; Split View, Slide Over и Stage Manager — вручную.
- [ ] Валидация архива с семейством устройств «1,2» в App Store Connect (T004) — нужна учётка.
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
- **Unit-тесты:** `bash scripts/test-fast.sh` → exit 0, включая `IPadLayoutPolicyTests`, `RecipesSelectionTests`, `IPadShellItemTests`, `AppLayoutModeTests`, `ShakeToOpenAssistantPreferenceTests`.
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
  - Полный откат — revert ветки. Переход на `[RecipesRoute]` можно оставить: он не меняет поведение.
- **Что будет взаимодействовать с изменением в будущем:**
  - любые новые вкладки (`AppTab`) — их нужно добавить и в `AppShellTabRoots`, и в `IPadShellItem`;
  - новые блоки рецепта — решить, в какую колонку;
  - новые листы — решить, поповер или form sheet на iPad;
  - Mac Catalyst или «Designed for iPad»;
  - будущая спека с «ассистент видит рецепт» и сеткой авторов;
  - сайдбар на iPadOS 18+ (Q1, низкий приоритет) — третий построитель таб-бара (Р3).
- **Временные allowlist/quarantine:** DEBUG-флаги `-DebugWindowWidth`, `-IPadSidebarHidden`, `-IPadListHidden` — owner: эта фича; только `#if DEBUG`; убираются, если появится штатный способ задавать ширину окна симулятора из UI-тестов.
