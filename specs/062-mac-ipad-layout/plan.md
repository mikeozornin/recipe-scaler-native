# План: Mac layout — native macOS и iPad regular

**Ветка**: `043-mac-ipad-layout`
**Дата актуализации**: 2026-08-10
**Спека**: [spec.md](./spec.md)
**Tasks**: [tasks.md](./tasks.md)
**Web reference**: `/Users/mike/work/git-repos/projects/recipe-scaler/recipe-scaler-web/recipe-scaler`

**Canonical feature path**: `specs/062-mac-ipad-layout`.
Ветка разработки сохраняет историческое имя `043-mac-ipad-layout`.

## Точка отсчёта после синхронизации

WIP-коммит ветки переналожен поверх актуального `master`:

- `master`: `bcfa2b0` (`Harden Yjs session and collection recovery`);
- текущий WIP: `2f8f13b`;
- `master...HEAD`: `0 1` — в ветке один коммит, поверх мастера нет пропущенных коммитов;
- generic iOS build после реализации platform boundaries: `BUILD SUCCEEDED`;
- generic macOS build для схемы `RecipeScalerMac`: `BUILD SUCCEEDED`;
- iOS `build-for-testing` для схемы `RecipeScalerNative`: `BUILD SUCCEEDED`; iPad Simulator теперь доступен, локальный shell smoke запущен и подтверждён через AX;
- `bash scripts/audit-ui-layout.sh specs/062-mac-ipad-layout`: `STATIC PASS`, manual acceptance pending;
- `scripts/resolve-simulator.sh` исправлен и умеет выбирать `SIM_DEVICE_FAMILY=iphone|ipad|any`; доступны iPhone Air и iPad Air 11-inch (M3);
- backend-independent iPad smoke прошёл: wide landscape показывает sidebar без bottom tabs, compact portrait сохраняет bottom tabs без sidebar, а sidebar routes открывают Discover/Shopping/Profile/Import; iPhone compact smoke также прошёл.
- native Mac runtime smoke после запуска debug-билда: `RecipeScalerMac` стартует без fatal error, показывает sidebar + recipe list + detail, а инструкции отображаются через markup parser; отдельные Discover/Shopping/Profile surfaces открываются в двухколоночном shell.

Решения, которые считаем принятыми для дальнейшей работы:

1. Mac — отдельный native macOS target, не Catalyst и не web-wrapper.
2. Первый вертикальный срез — Recipes на Mac: sidebar, список, папки, detail, selection и row actions.
3. После Mac-среза доводим тот же shared shell на iPad regular и затем остальные разделы.
4. Chrome следует HIG/SwiftUI; web используется как эталон структуры и поведения, а не как pixel-copy.
5. `InteractionProfile` ортогонален `LayoutMode`: iPad остаётся touch-профилем, Mac получает pointer-поведение.

## Что уже сделано

- Добавлены `LayoutMode`, `InteractionProfile`, debug override `forceLayout` и базовые unit-тесты.
- `AppShellView` выбирает compact/regular по `horizontalSizeClass`; compact-вариант вынесен в `CompactAppShell`.
- Добавлены `RegularAppShell`, системный `AppSidebarView`, recipes list/detail columns и toolbar entry points для assistant/timer.
- `AppShellCoordinator` получил wide selection, auto-select первого рецепта и маршрутизацию deep link/import в wide split.
- Wide auto-select теперь scoped к активной папке/виртуальной коллекции, а `lastRecipesRoute` восстанавливается и на iPad regular, и на Mac; смена папки сбрасывает устаревшую detail selection.
- Добавлен явный bridge compact↔regular: при переходе iPad из stack в split recipe переносится из pushed detail в третью колонку, а folder route остаётся в list column; обратный переход восстанавливает folder + recipe path.
- `RecipeListView` получил optional binding для wide selection; iPhone navigation path сохранён.
- iPad regular Recipes подключил folder/recipe selection и фактическую ширину list column к тому же validated `LayoutPreferencesStore`; iPad остаётся touch-профилем.
- `LayoutPreferencesStore` заведён с web-compatible ключами; Mac Recipes сохраняет route и фактическую ширину list divider, а Mac detail — ширину ingredients pane с clamp по min/max.
- `Package.swift` теперь объявляет iOS 17 + macOS 14; ZIPFoundation синхронизирована со SwiftPM и `Package.resolved`.
- `RecipeScalerCore` собирается для `arm64-apple-macosx`; Mac app target линкуется с тем же Core.
- Rust stable и Apple targets установлены в рабочем окружении; временная сборка y-crdt `v0.26.0` создала универсальный macOS Yrs slice и прошла `xcodebuild -create-xcframework`.
- Репозиторный XCFramework обновлён и содержит `macos-arm64_x86_64`, `ios-arm64`, `ios-arm64_x86_64-simulator`.
- Xcode project получил `RecipeScalerMac` target, shared scheme, Mac resources/framework phase и target membership только для Mac-compatible sources.
- Реализован Mac Recipes vertical slice: sidebar, collections/flat list, folder route, selection/detail, create/import entry points, pin, shopping, collections assignment, confirmed delete, context menu, hover strip и AppKit horizontal trackpad event state machine.
- Mac root явно включает regular-split routing, дренирует `DeepLinkRouter` после cold launch/auth и разрешает ожидающий recipe deep link после появления collection entries; import/deep link больше не попадают в iOS `NavigationPath` на Mac.
- Mac `WindowGroup` получил default `1280×800` и native minimum `960×640`, чтобы sidebar/list/detail сохраняли рабочую геометрию при resize.
- Реализованы native Mac surfaces для Discover (nested collection/profile/recipe routes), Shopping (Yjs CRUD, sort, share) и Profile (account/sharing/preferences/sync/logout); Assistant получил keyboard-first streaming sheet.
- Mac commands работают через notification bridge к `MacRootView`, а `AppContainer` явно инжектится в SwiftUI environment для views/sheets; для bundled `RecipeScalerCore` исправлен Mac runpath `@executable_path/../Frameworks`.
- Mac recipe detail переиспользует `RecipeDescriptionParser` через native SwiftUI renderer: HTML-теги не показываются как текст, custom timer links перехватываются через `OpenURLAction` и создают timer через общий `TimerManager`.
- После отдельного review-agent закрыты action/lifecycle gaps: Mac trackpad больше не использует `DragGesture`, row actions включают collections assignment, destructive delete подтверждается, Mac bootstrap устанавливает image-cache observers, а started timer публикуется уже после `timer.start()`; Assistant получил hover/context-menu copy и timestamp.
- Mac pointer rows теперь раскрывают action strip и при keyboard focus; recipe/shopping actions получили стабильные accessibility labels/identifiers, Assistant send доступен через `⌘Return`, а Import — через позиционную `⌘2` и mnemonic alias `⌘I`.
- Trackpad neutral-between-strips вынесен в общий `TrackpadActionStripState`; `AdaptiveLayoutTests` проверяет `leading → neutral → trailing`, touch profile и route/width persistence.
- В существующий iOS UI-test target добавлены `RegularRecipesShellSpec` и `RegularShoppingShellSpec` с `-ForceLayout=wide`: sidebar/no-bottom-tabs, selection→detail, recipe touch `swipeLeft`→trailing delete и Shopping touch `swipeLeft`→trailing delete assertions; Simulator test bundle компилируется. Live local-backend run теперь проходит через DEBUG-only Socket.IO polling и подтверждает selection→detail и обе touch actions; при отсутствии backend тесты по-прежнему явно `XCTSkip`, чтобы окружение не маскировалось под layout failure. Page object ищет wide recipe row по stable identifier независимо от AX-роли (`Button` в compact, `Any` в regular), а touch actions имеют locale-independent IDs.
- Добавлен `AdaptiveShellLocalSmokeSpec` без backend-зависимости: wide-сценарий сам переводит iPad в landscape, compact-сценарий — в portrait; AX-инварианты shell подтверждены на iPad и iPhone.
- Исправлен iOS regular routing bug: Recipes использует отдельный 3-column `NavigationSplitView`, остальные regular surfaces — настоящий 2-column split без пустой промежуточной колонки; local AX smoke проверяет переключение Discover/Shopping/Profile/Import.
- Mac detail получил `HSplitView` для ingredients/instructions при ширине от 640 pt и единый вертикальный scroll fallback для узких окон; iPad detail пока остаётся shared iOS surface.
- Mac использует общий `AppContainer`/`YjsSyncService`/`AuthService`/`TimerManager`; iOS-only WebView, Live Activities, widgets, reminders/Spotlight surfaces не входят в Mac target.
- Platform wrappers добавлены для symbols, typography/colors, toolbar, timers, Watch bridge и image upload preprocessing; iOS compact path сохранён.
- Добавлены исходные spec/layout/research/contracts документы.

## Остаток после текущего вертикального среза

| Область | Фактическое состояние | Следствие для плана |
|---|---|---|
| macOS target | `RecipeScalerMac` target/scheme, native `WindowGroup`, корректный embedded-framework runpath, startup smoke и локальный universal archive существуют; generic build зелёный | Нужен signed distribution path и полноценная human accessibility acceptance |
| Yrs / Core | Репозиторный XCFramework содержит macOS slice; iOS и Mac generic builds зелёные | Остаётся проверить cold launch и sync/auth на реальном Mac; iPad/iPhone shell AX smoke уже пройден |
| Исполняемый shell | iOS идёт через `ContentView → AppShellView`; Mac идёт через `RecipeScalerMacApp → RegularAppShell`; Mac Recipes использует 3 колонки, остальные Mac surfaces — 2 колонки; оба получают shared coordinator/container contracts | Дублирующий `AdaptiveAppShell.swift` удалён из iOS source phase; iPad mode transitions и runtime accessibility остаются |
| iPad regular | Shared `RegularAppShell` и iOS Recipes split компилируются; folder/selection model, compact↔regular bridge и list-width owner подключены; local AX smoke, live selection→detail и live touch `swipeLeft`→delete проверены на iPad | Остались Stage Manager, реальный compact↔regular transition, Mac pointer/trackpad acceptance и human accessibility review |
| Mac interactions | Recipes rows используют pointer profile: hover, keyboard focus, context menu и AppKit `scrollWheel` с neutral-before-opposite state machine; доступны pin/cart/collections/delete с подтверждением и stable AX IDs. Shopping имеет hover/focus/context-menu delete; `.swipeActions` не попадает в Mac target. Assistant footer показывает copy/timestamp on hover и через context menu, send поддерживает `⌘Return` | Нужны focused runtime checks жестов и accessibility |
| Width persistence | Route, iPad list divider, Mac list divider и Mac ingredients pane width сохраняются в validated UserDefaults keys; `AdaptiveLayoutTests` проверяет clamp, valid width и route round-trip | Нужен runtime check drag/relaunch; iPad system divider acceptance не подтверждён simulator-ом |
| Detail split | Mac detail использует `HSplitView` при ширине ≥640 pt и vertical scroll fallback ниже порога; markup parser и timer links работают в runtime; iOS detail сохранён shared | Runtime acceptance minimum widths; Mac rich description editing остаётся вне scope platform spike |
| Остальные Mac surfaces | Discover/Shopping/Profile/Assistant — native implementations; Import — native file sheet; Discover/Shopping/Profile открыты в smoke | Нужна проверка Import/Assistant/offline/error flows и accessibility |
| Human acceptance | `layout-audit.json` и static audit PASS | Нужны human review `layout.md`, accessibility/interaction acceptance и matching `layout-acceptance.json` |
| Состояние WIP | Удалены `DeviceAuthMetadata.swift`, `LegacyAuthMigrationBanner.swift` и дублирующий `StartTenMinuteTimerIntent.swift` | Cleanup выполнен; новые target memberships не должны возвращать эти файлы |
| Spec ID | Документы перенесены в `specs/062-mac-ipad-layout`; ветка остаётся `043-mac-ipad-layout` | Canonical path больше не конфликтует с `specs/043-ingredient-illustrations` |

## Границы

- **В scope**: shared adaptive shell; native macOS target; Recipes vertical slice на Mac; iPad regular shell; touch/pointer row actions; local layout preferences; deep links, import, offline/auth lifecycle в новом shell; accessibility и i18n.
- **Вне scope**: backend/API changes; новый sync protocol; изменение Y.Doc schema; watchOS, widgets, Live Activities, Share/Action extensions на macOS; переписывание Tiptap/description editor до отдельного platform spike.
- **STOP conditions**:
  - если `RecipeScalerCore` или Yrs нельзя собрать для macOS без существенной смены ABI, остановить Mac implementation на feasibility report и не маскировать проблему Catalyst-обёрткой;
  - если `layout.md` не прошёл human review и нет `layout-audit.json`, не добавлять новые SwiftUI layout tasks;
  - не создавать второй `AppContainer`, `YjsSyncService`, `AuthService` или timer lifecycle для Mac;
  - не выдавать iPad pointer-only affordances и не использовать iOS `.swipeActions` как Mac UX.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|---|---|---|
| CRDT-first | PASS | Shell читает существующие `YjsSyncService.collectionEntries` и вызывает существующие mutation APIs; layout state не попадает в Y.Doc |
| Web parity | PASS for mapped v1 behavior / PARTIAL for runtime | Web behavior mapped from `src/App.tsx`, `src/utils/main-nav.ts`, `AdaptiveRow`/`DesktopScrollableRow`; native routes/actions and persistence implemented, runtime parity remains unverified |
| Offline-first | PASS | Mode/selection/layout are local; sync/auth remain owned by `AppContainer`; layout switch must not recreate the sync session |
| Native UI | PASS for build boundary / PARTIAL for acceptance | Native Mac target, WindowGroup, NavigationSplitView, two/three-column shell and platform wrappers compile; startup/AX smoke passes, human acceptance is pending |
| Phased delivery | PASS | Mac Recipes vertical slice is isolated before iPad/other surfaces and nested detail split |
| i18n | PASS with gate | Existing shell keys are in `Localizable.xcstrings`; all new menu/action copy must go through project catalogs and `lint-i18n.sh` |
| Documentation | PARTIAL | Canonical docs and `layout-audit.json` exist; human acceptance and `layout-acceptance.json` are pending |

## Очерёдность

### P0. Нормализация WIP и платформенный feasibility spike

1. Перенести документы в `specs/062-mac-ipad-layout/` и обновить ссылки — выполнено.
2. Проверить и удалить либо явно подключить stale files из WIP: duplicate timer intent, auth metadata и legacy banner — выполнено удалением неиспользуемых файлов.
3. Составить platform matrix для `RecipeScalerCore`, Yrs, GRDB, KeychainAccess, SocketIO, EventKit, WebKit, App Intents и UIKit-only helpers — выполнено через target membership/platform wrappers и Mac compile gate; runtime-only OS surfaces явно исключены.
4. Проверить `Package.swift`, `YrsXCFramework.xcframework/Info.plist` и `scripts/build-yrs-xcframework.sh` на macOS — выполнено; script создаёт три ожидаемых platform slices.
5. Установить проверенный XCFramework в `Frameworks/` и проверить iOS build до создания Mac target — выполнено.

### P1. Layout gate и convergence shared shell

1. Обновить `layout.md` под первый Mac recipes slice и iPad regular; добавить `layout-audit.json` с falsifiable claims — выполнено, static audit PASS.
2. Получить human review `layout.md`; после этого прогнать static audit — static audit выполнен, human review pending.
3. Оставить один runtime path внутри каждого executable: iOS `ContentView → AppShellView`, Mac `RecipeScalerMacApp → RegularAppShell`; shared coordinator/services сохранены; исторический `AdaptiveAppShell` удалён из target.
4. Убрать UIKit-only `TabBarTopOffsetReader` из Mac compilation и оставить UIKit import за conditional boundary — выполнено для Mac target; iOS path не изменён.
5. Сохранить один `AppShellCoordinator` и один set of injected services — выполнено; Mac entry использует container-owned instances.

### P2. Mac target и Recipes vertical slice

1. Создать `RecipeScalerMac` target/scheme с `WindowGroup`, minimum window size, titlebar/sidebar commands и `AppContainer` composition root — выполнено; generic Mac build и startup smoke зелёные.
2. Сделать macOS compile boundary для system color, WebKit, file import, haptics, notifications, keyboard/menu commands и iOS extensions — выполнено для текущего Recipes slice; iOS-only editor/OS surfaces исключены.
3. Подключить `RegularAppShell` как Mac root: sidebar → recipes list → selected detail — выполнено.
4. Завершить Recipes behavior: flat/collection folder routes, selected recipe restoration, empty state, create/import, pin, add-to-shopping и delete — compile/static implementation и базовый 3-column startup/selection smoke выполнены; destructive/action matrix acceptance pending.
5. Ввести shared row-action contract с двумя adapters — выполнен Mac adapter для Recipes, iOS `.swipeActions` сохранён:
   - touch: visible/accessible `.swipeActions` и actions without hover;
   - pointer: `onHover` reveal, keyboard focus, `contextMenu` и AppKit horizontal trackpad `scrollWheel`/strip по parity с web `DesktopScrollableRow`.
6. Добавить Mac keyboard commands (`⌘1…⌘5`, `⌘I` для дополнительного Import alias, assistant, sidebar) — выполнено; notification routing проверена, focus/selection runtime check pending.

### P3. iPad regular acceptance

1. Прогнать iPad regular Recipes end-to-end в landscape/Stage Manager и iPad compact fallback — backend-independent shell smoke, live local-backend selection→detail и touch swipe action выполнены; Stage Manager acceptance остаётся.
2. Синхронизировать selection при compact↔regular и при rotation; coordinator bridge и folder/list route реализованы, backend-dependent detail selection и реальный resize/rotation остаются.
3. Сохранить touch profile на iPad, включая iPad с trackpad: platform boundary и `.swipeActions` сохранены; live iPad `swipeLeft`→delete проверен, остаётся ручная проверка trackpad/no-hover поведения.
4. Подключить остальные regular surfaces: Discover, Shopping, Profile, Import и Assistant — Mac surfaces реализованы, iPad route smoke для первых четырёх и regular Assistant toolbar smoke прошли, полноценные surface/accessibility acceptance остаются.

### P4. Persistence, detail split и polish

1. Сохранить/восстановить iPad/Mac list width и Mac ingredients width; clamp значения по min/max — реализовано в `LayoutPreferencesStore` и column owners, runtime drag/relaunch check pending.
2. Сохранить recipes route/folder в согласованном UserDefaults scope; при logout/account switch очистить transient selection, не удаляя layout preference без явного требования.
3. Реализовать nested detail split для Mac после static minimum-width gate; ниже порога оставить один scrollable detail — реализовано; iPad regular rich detail split остаётся отдельным runtime-polish этапом.
4. Добавить accessibility labels/selection traits и keyboard focus — code-level contract выполнен; sidebar collapse, adjustable system dividers и UI smoke остаются runtime acceptance.

## Изменения

| Файл / область | Действие | Почему |
|---|---|---|
| `specs/062-mac-ipad-layout/` | Canonical feature docs, layout contract and static audit evidence | Номер 043 уже занят другим feature на master |
| `Package.swift`, `Frameworks/YrsXCFramework.xcframework`, `scripts/build-yrs-xcframework.sh` | Установить проверенный XCFramework; сохранять воспроизводимый iOS+macOS build script | Native Mac target должен линковаться с macOS Yrs slice |
| `RecipeScalerNative.xcodeproj/project.pbxproj`, `RecipeScalerMac/` | Создать Mac target, scheme, resources/framework phase и app entry | Native Mac executable и target boundary |
| `AppContainer.swift`, `ContentView.swift`, `AppShellView.swift` | Оставить composition root и platform-neutral shell entry | Все target'ы должны использовать один auth/sync/timer lifecycle |
| `Views/AdaptiveAppShell/*` | Свести исторический duplicate scaffold до одного iOS runtime path и shared regular components | iOS `AppShellView` — единственный executable entry; Mac использует `RegularAppShell` напрямую |
| `AppShellCoordinator.swift`, `RecipeListView.swift` | Завершить route/selection model для wide mode и mode transitions | Wide state хранит selected recipe + active folder и мостит compact `NavigationPath` в regular selection |
| `LayoutPreferencesStore.swift` | Добавить validated read/write API и owner resize events | Route, list divider и Mac inner divider используют общие clamped keys |
| `Views/*Row*`, `ShoppingListView`, `YDocIngredientsSection`, assistant footer | Добавить shared touch/pointer action adapters | Recipes/Shopping Mac adapters и Mac Assistant hover/context actions реализованы; iOS touch path не меняется |
| `Localizable.xcstrings`, `AccessibilityIdentifiers.swift` | Добавить только недостающие Mac/sidebar/menu/action keys и identifiers | Соблюдение i18n, Martian typography и UI-test contract |
| `RecipeScalerNativeTests`, `RecipeScalerNativeUITests`, feature verify scripts | Добавить positive invariants по shell, selection, actions, persistence и target build | Компиляция не доказывает UX-поведение |

## Downstream consumers

- **SwiftUI views**: `ContentView`, `AppShellView`, `CompactAppShell`, `RegularAppShell`, `AppSidebarView`, `RecipeListView`, `CollectionFolderView`, `YDocRecipeDetailView`, `ShoppingListView`, `DiscoverRootView`, `AccountView`, `AssistantSheet`, `MobileTimerPanel`.
- **Cross-process**: `AppContainer` и `AppShellCoordinator` остаются canonical owners; App Intents/deep links/Spotlight должны открывать правильную compact или regular presentation. WatchOS, widgets, Live Activity и Share/Action extensions не получают Mac target membership.
- **Sync boundaries**: `YjsSyncService.collectionEntries`, recipe/folder mutation methods, `DeepLinkRouter`, file import coordinator и existing API contracts; server changes не планируются.
- **Persisted state**: `UserDefaults` keys `layout.recipe-list-width`, `layout.recipe-ingredients-width`, `layout.last-recipes-route`; selection/path/transient presentation должны быть очищаемыми при logout/account switch.
- **Tests / verify scripts**: `AdaptiveLayoutTests`, `AppShellCoordinatorTests`, existing `TabBarDiscoveryTests`, UI smoke, `lint-i18n.sh`, `audit-ui-layout.sh`, iOS and Mac build/test schemes.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|---|---|---|
| Compact launch | На iPhone и iPad compact видны bottom tabs; повторный tap таба сбрасывает только его nested path | `RecipeScalerNativeTests/AppShellCoordinatorTests` + UI smoke |
| Regular launch | На iPad regular и Mac есть sidebar; Recipes показывает list column и detail column, остальные iOS regular surfaces используют sidebar + content без пустой средней колонки | `AdaptiveShellLocalSmokeSpec` regular shell + route tests; Mac AX smoke |
| Wide selection | Tap recipe меняет `wideRecipesState.selectedRecipeId`, detail обновляется без добавления `recipesPath` | `AppShellCoordinatorTests/test_wideSplit_openRecipeDetail` + `RegularRecipesShellSpec.test_regularRecipeSelectionUsesDetailColumn` |
| Empty/loaded collection | При непустом collection автоматически выбирается первый не deleted recipe; при пустом collection показывается localized empty state | `RegularRecipesShell` scenario |
| Mode switch | После compact↔regular выбранный recipe ID и active folder сохраняются, а `YjsSyncService`/session identity не меняется | `AppShellCoordinatorTests/test_regularLayoutTransition_preservesRecipeAndFolderAcrossModes` |
| Input profile | iPad recipe/shopping actions доступны без hover; Mac row actions доступны через hover/focus/context menu/trackpad path и не требуют finger swipe | iPad `RegularRecipesShellSpec.test_regularRecipeKeepsTouchSwipeActions` + `RegularShoppingShellSpec.test_regularShoppingKeepsTouchDeleteAction` (`Test-ipad-touch-swipe-local-test-schema.xcresult`, `Test-ipad-shopping-touch-delete.xcresult`, 1/1 each); Mac pointer/trackpad acceptance pending |
| Persistence | После изменения column width и relaunch значение восстанавливается и находится в clamp bounds | `AdaptiveLayoutTests/LayoutPreferencesStore` |
| Offline flow | При reconnect/offline transition shell сохраняет selection и queued Yjs mutations; layout changes не очищают offline queue | existing sync verify + `AdaptiveShellOffline` |
| Deep link/import | Open recipe, universal link и completed import выбирают Recipes и открывают detail в правильном mode | `AppShellCoordinatorTests` + UI smoke |
| Target health | `RecipeScalerNative` и `RecipeScalerMac` собираются без duplicate intent/source membership | xcodebuild build gates |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|---|---|---|---|---|
| App startup / `YjsSyncService.start` | auth user, session epoch, container identity | existing sync service re-checks session before publishing; shell only consumes current state | `AppContainer` | existing stale-session recovery tests |
| Recipe create/import/delete/pin/shopping action | user/session epoch + recipe ID + current folder context | mutation result must be applied only to the same session and still-relevant recipe | view task or coordinator-owned task; cancel on disappear/logout | `RecipesActionsStaleSession` |
| Collection-driven auto-select | collection snapshot identity; no suspension in selection reducer | N/A — pure MainActor state transition | SwiftUI view lifetime | `AppShellCoordinatorTests/test_wideSplit_autoSelectsFirstRecipeWithinActiveFolder` |
| Deep link waiting for collection entry | deep-link recipe ID + auth/session epoch | resolve only when entry is present and not deleted; otherwise keep pending | `AppShellCoordinator` / existing router lifecycle | existing Spotlight/deep-link tests extended for regular mode |
| Transient shopping status dismissal | displayed message token | compare token before clearing; a newer message wins | shell owns `Task`, cancels on replacement and teardown | `TransientStatusStaleDismissal` |
| Per-row image preload | recipe ID and file URL | ignore completion after row/recipe disappears; retain existing cache contract | row task, cancelled by SwiftUI | existing image-cache tests; no new network side effect |

Single-flight guards belong before the first `await`; every long-lived task must have an explicit owner and teardown path. Shell extraction must not silently create a second observer or duplicate `NotificationCenter` handling.

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|---|---|---|---|---|---|
| logout | reset coordinator tabs, paths, wide selection, import and pending links | AppContainer performs existing sync/timer teardown | keep validated layout widths; clear transient route/selection | unregister existing widget/live activity surfaces through AppContainer | next login starts at a safe Recipes root without stale recipe detail |
| account switch | invalidate old user selection and assistant context | cancel old recipe actions/status tasks before new session | do not expose old user route; layout defaults remain valid | no old-user deep link/import completion reaches new shell | new account gets current collection only |
| stale session / cold start | shell waits for injected services; no fallback singleton construction | existing session recovery owns retries; shell does not spawn duplicate sync | malformed layout values clamp to defaults | App Intents/Spotlight pending IDs remain explicit until resolvable | recovery can finish without replacing shell identity |
| reconnect / partial failure | retain selected recipe and visible mode | existing Yjs reconnect lifecycle remains owner; action tasks report errors | no reset of widths or last route | no duplicate notifications/observers | user can continue from the same selection after reconnect |
| Mac window close / scene teardown | release shell-local bindings and transient state | cancel status, import and row tasks owned by the scene | UserDefaults writes are atomic and validated | remove Mac-only menu/monitor hooks | reopening window creates presentation over the same AppContainer, not a second session |

## Cross-target contracts

- **Canonical owner**: `AppContainer` owns services; `AppShellCoordinator` owns navigation/selection; `LayoutPreferencesStore` owns device-local layout values; `InteractionProfile.current` owns platform input classification.
- **Writer/reader targets**: iOS compact/regular and native Mac shell read the same coordinator contract; iOS/Mac write the same validated UserDefaults keys; web remains a behavior reference and does not share native storage.
- **Validator/normalizer**: one `LayoutPreferencesStore` clamp/normalizer; one route adapter for compact `NavigationPath` versus regular selection; one platform adapter for touch/pointer row actions.
- **Raw literal exceptions**: no new UI copy or menu title literals outside localization catalogs; SF Symbol names are allowed as icon identifiers; UserDefaults keys remain centralized in `LayoutPreferencesStore`.

## Locale / theme consumers

- **SwiftUI environment**: sidebar labels, empty states, toolbar labels and menu commands use `AppTab.title`, localization keys and `.appBody()`/`.appFootnote()`; all text uses the Martian project typography.
- **UIKit / notification categories / scheduled content**: Mac target must not compile iOS UIKit appearance or tab-bar readers; existing iOS notification contracts stay unchanged.
- **Widgets / Live Activities / App Intents**: no new Mac surface; existing intents continue to target the iOS app and must not have duplicate source declarations.
- **Cached or generated assets**: no new image asset is required for shell; reuse current empty-state assets and `AppSymbol`.
- **`.system` effective value**: use platform-neutral SwiftUI colors or an explicit iOS/macOS adapter; do not carry `Color(.systemBackground)` with an implicit UIKit dependency into Mac sources.

## Compatibility / migration

- **Current format/contract**: existing Y.Doc, API, auth/session and deep-link contracts remain unchanged; layout keys are native-only local preferences.
- **Previous supported format**: missing `layout.*` values resolve to `320` list width, `400` ingredients width and `/` route; values below minimum are clamped.
- **Missing version/default behavior**: no schema version is needed for the first local layout release; add one only if column model changes.
- **Unknown future version/ID behavior**: invalid width/route falls back to safe default and logs a structured diagnostic; unknown recipe/folder route opens the root/empty state instead of fabricating a target.
- **Required legacy fixture tests**: old UserDefaults with zero, negative and oversized values; pending deep link for deleted recipe; missing Mac Yrs slice; duplicate App Intent source audit.

## Unknown IDs and fallback policy

- DEBUG/CI: unknown layout mode, route discriminator or platform capability is a hard test failure with the raw value in the diagnostic.
- Release: unknown persisted route or unavailable capability resolves to localized root/empty state and emits `AppLog` context; never use prefix-based semantic fallback.
- Legacy aliases: keep explicit mapping in the route adapter only; remove the adapter when the last legacy fixture is retired.

## Generated resources

| Resource | Manifest | Source output | Installed path | Built `.app`/`.appex` assertion |
|---|---|---|---|---|
| macOS Yrs binary, if binary route is chosen | `YrsXCFramework.xcframework/Info.plist` | `scripts/build-yrs-xcframework.sh` | Mac app Frameworks | Mac scheme links the macOS slice and does not link an iOS-only binary |
| layout audit | `specs/062-mac-ipad-layout/layout-audit.json` | hand-authored static claims | not packaged | `audit-ui-layout.sh` reports `STATIC PASS`; human acceptance is separate |
| shell images | existing asset catalog | existing sync/build pipeline | native app resources | no new shell-specific asset is required |

## Human gates

- [x] Перенести документы с конфликтующего номера 043 на canonical feature number.
- [ ] `layout.md` reviewed by human: sidebar/list/detail tree, min widths, compact/regular states, Mac pointer states.
- [x] Добавить `layout-audit.json` и получить `STATIC PASS`.
- [ ] Добавить `layout-acceptance.json` с matching hash после human review; `STATIC PASS` не считать финальной приёмкой.
- [x] Выполнить отдельный review-agent после реализации shell; findings по trackpad/actions/delete/timer/bootstrap/assistant устранены.
- [x] Выполнить локальный Mac startup/AX smoke: Recipes 3-column, non-Recipes 2-column, Discover/Shopping/Profile navigation и parsed instructions.
- [ ] Провести accessibility acceptance на iPad regular и native Mac window.

## Verification

### Evidence уже получено для синхронизации

- `git rev-list --left-right --count master...HEAD` → `0 1`.
- `xcodebuild -quiet -scheme RecipeScalerNative -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/recipe-scaler-ios-universal-yrs-build CODE_SIGNING_ALLOWED=NO build` → exit `0`, `BUILD SUCCEEDED` после удаления historical `AdaptiveAppShell`.
- `xcodebuild -quiet -scheme RecipeScalerNative -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/recipe-scaler-ios-tests-build CODE_SIGNING_ALLOWED=NO build-for-testing` → exit `0`, `BUILD SUCCEEDED`; historical compile gate, runtime evidence приведён ниже.
- `xcodebuild -quiet -scheme RecipeScalerMac -destination 'generic/platform=macOS' -derivedDataPath /private/tmp/recipe-scaler-mac-surface-build CODE_SIGNING_ALLOWED=NO build` → exit `0`, `BUILD SUCCEEDED` после review fixes; nested detail split, AppKit trackpad monitor, native assignment sheet and Mac surfaces compile, warnings only.
- После Mac deep-link fix: `xcodebuild -quiet -scheme RecipeScalerMac -destination 'generic/platform=macOS' -derivedDataPath /private/tmp/recipe-scaler-mac-deeplink-fix-build CODE_SIGNING_ALLOWED=NO build` → exit `0`; iOS `build-for-testing` с coordinator regression test → exit `0`.
- После compact↔regular bridge и Mac menu cleanup: Mac `xcodebuild` с `-derivedDataPath /private/tmp/recipe-scaler-mac-menu-cleanup-build` → exit `0`; iOS `build-for-testing` с `-derivedDataPath /private/tmp/recipe-scaler-ios-folder-selection-tests-build` → exit `0`.
- Последний Mac compile gate: `xcodebuild -quiet -scheme RecipeScalerMac -destination 'generic/platform=macOS' -derivedDataPath /private/tmp/recipe-scaler-mac-debug-autologin-build CODE_SIGNING_ALLOWED=NO build` → exit `0` после Mac two/three-column shell split и native markup renderer; warnings только из существующего `YrsDocument` actor-isolation gate.
- Последний iOS test compile gate после persistence invariant: `xcodebuild -quiet -scheme RecipeScalerNative -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/recipe-scaler-ios-appcontainer-build CODE_SIGNING_ALLOWED=NO build-for-testing` → exit `0`; test bundle включает valid-width round-trip, runtime smoke evidence приведён ниже.
- После keyboard/accessibility и trackpad state-machine изменений: Mac `xcodebuild -quiet -skipPackageUpdates -scheme RecipeScalerMac -destination 'generic/platform=macOS' -derivedDataPath /private/tmp/recipe-scaler-mac-debug-autologin-build CODE_SIGNING_ALLOWED=NO build` → exit `0`; iOS `xcodebuild -quiet -skipPackageUpdates -scheme RecipeScalerNative -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/recipe-scaler-ios-appcontainer-build CODE_SIGNING_ALLOWED=NO build-for-testing` → exit `0`.
- После добавления `RegularRecipesShellSpec` и sidebar selectors: `xcodebuild -quiet -skipPackageUpdates -scheme RecipeScalerNative -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/recipe-scaler-ios-appcontainer-build CODE_SIGNING_ALLOWED=NO build-for-testing` → exit `0`; создан `Debug-iphonesimulator/RecipeScalerNativeUITests-Runner.app/PlugIns/RecipeScalerNativeUITests.xctest`.
- После добавления локального shell smoke и ориентационной стабилизации: тот же iOS Simulator `build-for-testing` → exit `0`.
- Mac Release compile gate: `xcodebuild -quiet -scheme RecipeScalerMac -configuration Release -destination 'generic/platform=macOS' -derivedDataPath /private/tmp/recipe-scaler-mac-release-build CODE_SIGNING_ALLOWED=NO build` → exit `0`; `otool -l` подтверждает `@executable_path/../Frameworks` в Release executable.
- Mac Release archive gate: `xcodebuild -quiet -skipPackageUpdates -scheme RecipeScalerMac -configuration Release -archivePath /private/tmp/recipe-scaler-mac-release.archive CODE_SIGNING_ALLOWED=NO archive` → exit `0`; `/private/tmp/recipe-scaler-mac-release.archive.xcarchive` содержит `RecipeScalerMac.app`, `RecipeScalerCore.framework`, dSYM и arm64/x86_64 executable. Code signing intentionally disabled for the local packaging gate.
- `swift build --target RecipeScalerCore --triple arm64-apple-macosx --scratch-path /private/tmp/recipe-scaler-core-macos-probe` → exit `0`, `Build of target: 'RecipeScalerCore' complete`.
- `bash scripts/build-yrs-xcframework.sh /private/tmp/y-crdt-026 /private/tmp/recipe-scaler-yrs-macos-probe` → exit `0`; `Info.plist` временного output содержит `ios-arm64`, `ios-arm64_x86_64-simulator`, `macos-arm64_x86_64`; `lipo -info` подтверждает ожидаемые архитектуры.
- Репозиторный `Frameworks/YrsXCFramework.xcframework/Info.plist` теперь содержит `macos-arm64_x86_64`; Mac target действительно линкуется с этим slice.
- `bash scripts/audit-ui-layout.sh specs/062-mac-ipad-layout` → `STATIC PASS` с проверкой AppKit `scrollWheel`, keyboard focus и Mac action accessibility; четыре manual claims остаются pending.
- Computer Use startup smoke на `/private/tmp/recipe-scaler-mac-debug-autologin-build/Build/Products/Debug/RecipeScalerMac.app -DebugMacAutoLogin=1` → no crash; AX tree подтвердил app sidebar + recipe list + selected detail, `HSplitView`, parsed instruction text и toolbar IDs. Read-only navigation дополнительно открыла Discover, Shopping и Profile без пустой средней колонки.
- Read-only Mac interaction smoke → recipe context menu exposes `Add to collection`, `Pin`, `Add to shopping list`, `Delete`; menu закрывается Escape, destructive action не выполнялась.
- Свежий Computer Use/AX smoke после keyboard/accessibility polish → focused recipe row объявляет `Add to collection`, `Add to shopping list`, `Pin`, `Delete`; `⌘K` открывает `assistant_sheet` с focused composer; sidebar Import открывает `import_sheet`; system splitters объявлены settable; все sheets закрыты Escape.
- Свежий Mac AX smoke после добавления mnemonic alias → `⌘I` открывает тот же native `import_sheet`, фокус попадает на `Choose file`; sheet закрыт без выбора файла.
- Runtime smoke выявил и исправил две упаковочные/композиционные проблемы: Mac framework runpath должен указывать на `Contents/Frameworks`, а `MacAppCommands` не может читать SwiftUI view environment; menu actions теперь идут через notification bridge.
- `bash scripts/lint-i18n.sh`, `bash scripts/policy-check.sh`, `git diff --check`, JSON parse `layout-audit.json`/`Localizable.xcstrings`, `verify-plan-policy.py` → exit `0`.
- `SIM_DEVICE_FAMILY=iphone bash scripts/resolve-simulator.sh` → iPhone Air `E42E8F7B-092F-4752-AAFC-28F52373737E`; `SIM_DEVICE_FAMILY=ipad bash scripts/resolve-simulator.sh` → iPad Air 11-inch (M3) `4B899C3B-38E5-40CC-AB61-AAA83B7D3E27`.
- После refactor iOS regular 3/2-column shell: `xcodebuild -quiet -skipPackageUpdates -scheme RecipeScalerNative -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/recipe-scaler-ios-appcontainer-build CODE_SIGNING_ALLOWED=NO build-for-testing` → exit `0`; условная Mac-ветка того же shared view дополнительно прошла `RecipeScalerMac` generic build в `/private/tmp/recipe-scaler-mac-debug-autologin-build`.
- Unit contracts после shell refactor: `xcodebuild ... -only-testing:RecipeScalerNativeTests/AdaptiveLayoutTests -only-testing:RecipeScalerNativeTests/AppShellCoordinatorTests test` → exit `0`; layout resolver, touch/pointer profile, neutral trackpad state, width/route persistence и coordinator mode/deep-link cases passed.
- Свежий iPad AX smoke после фикса пустой средней колонки: `xcodebuild ... -only-testing:RecipeScalerNativeUITests/AdaptiveShellLocalSmokeSpec test-without-building` → exit `0`; xcresult `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-after-detail-width.xcresult`, 3/3 passed на iPad Air 11-inch (M3), iOS 26.3.1: compact tabs, regular sidebar/no bottom tabs, Discover/Shopping/Profile/Import routes.
- `simctl log` показал только iOS 26 Simulator fault `com.apple.runtime-issues/SwiftUI: Invalid frame dimension (negative or non-finite)` в момент анимации системного `Show Sidebar`; тот же smoke завершился 3/3 без failures, а backtrace указывает на `SwiftUICore` transition, не на app-level dynamic frame. Это отмечено как simulator observation; production layout не получил обходного custom sidebar.
- Свежий iPhone compact AX smoke: `xcodebuild ... -only-testing:RecipeScalerNativeUITests/AdaptiveShellLocalSmokeSpec/test_compactShellKeepsBottomTabsWithoutSidebar test-without-building` → exit `0`; xcresult `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-iphone-compact-after-width.xcresult`, 1/1 passed на iPhone Air, iOS 26.3.1.
- Свежий iPad regular Assistant smoke без backend: `xcodebuild ... -only-testing:RecipeScalerNativeUITests/AdaptiveShellLocalSmokeSpec/test_regularAssistantUsesToolbarWithoutCompactFab test-without-building` → exit `0`; xcresult `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-ipad-regular-assistant-final.xcresult`, 1/1 passed на iPad Air 11-inch (M3): toolbar action присутствует, compact FAB отсутствует, sheet открывается.
- Последний последовательный backend-independent iPad shell run на актуальном UI-test bundle: `xcodebuild ... -only-testing:RecipeScalerNativeUITests/AdaptiveShellLocalSmokeSpec test-without-building` → exit `0`; xcresult `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-ipad-shell-final-current-serial.xcresult`, 4/4 passed на iPad Air 11-inch (M3). Последний iPhone compact run — `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-iphone-compact-final-current.xcresult`, 1/1 passed.
- Полный `RegularRecipesShellSpec` без локального web backend остаётся best-effort: при отсутствии fixture backend `BaseTestCase` корректно soft-skipped его после `NSURLError -1004` к loopback; локальный selection E2E ниже запускается против отдельного backend.
- Свежий iPad selection-gate с изолированным local backend: `xcodebuild ... -only-testing:RecipeScalerNativeUITests/RegularRecipesShellSpec/test_regularRecipeSelectionUsesDetailColumn test-without-building` → exit `0`; xcresult `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-regular-selection-e2e-local-20.xcresult`, 1/1 passed на iPad Air 11-inch (M3), iOS 26.3.1. REST seed, DEBUG-only polling Socket.IO handshake, collection sync, row tap и `recipe_detail_menu` подтверждены.
- Свежий iPad touch-action gate с изолированным local test-schema backend: `xcodebuild ... -only-testing:RecipeScalerNativeUITests/RegularRecipesShellSpec/test_regularRecipeKeepsTouchSwipeActions test-without-building` → exit `0`; xcresult `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-ipad-touch-swipe-local-test-schema.xcresult`, 1/1 passed на iPad Air 11-inch (M3), iOS 26.3.1. REST seed, collection sync, `swipeLeft` и `recipe_row_delete_<id>` accessibility ID подтверждены.
- Свежий iPad Shopping touch-action gate с тем же изолированным local test-schema backend: `xcodebuild ... -only-testing:RecipeScalerNativeUITests/RegularShoppingShellSpec/test_regularShoppingKeepsTouchDeleteAction test-without-building` → exit `0`; xcresult `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-ipad-shopping-touch-delete.xcresult`, 1/1 passed на iPad Air 11-inch (M3), iOS 26.3.1. Свободный shopping item, finger `swipeLeft` и `shopping_item_delete_<id>` accessibility ID подтверждены.
- После добавления стабильных touch-action selectors: unit contracts прошли в `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-unit-final.xcresult`; backend-independent iPad regular shell smoke — `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-adaptive-shell-final.xcresult`, 3/3 passed; iPhone compact smoke — `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-iphone-compact-final.xcresult`, 1/1 passed.
- После явного Shopping `.swipeActions` и нового UI-test contract: iOS `build-for-testing` и Mac generic build завершились с exit `0`; unit contracts — `/private/tmp/recipe-scaler-ios-appcontainer-build/Test-unit-shopping-final.xcresult`, 28/28 passed на iPad Air 11-inch (M3).
- Для loopback E2E `RecipeScalerCore` Debug-конфигурация теперь действительно компилируется с `DEBUG`; harness сохраняет/нормализует `http://` URL, а Release не принимает loopback override. Это устранило ложный ATS failure без изменения production transport.
- Последний iOS Simulator `build-for-testing` после Core DEBUG/loopback harness и wide-row AX selector изменений → exit `0`; source-level и runtime selection contracts компилируются и проходят.
- Финальные compile gates после удаления временной диагностики: iOS Simulator `build-for-testing` → exit `0` (`/private/tmp/recipe-scaler-ios-appcontainer-build`), Mac Debug generic build создал `/private/tmp/recipe-scaler-mac-final-build/Build/Products/Debug/RecipeScalerMac.app`, Mac Release generic build → exit `0` (`/private/tmp/recipe-scaler-mac-final-release`); Release app сохраняет `NSAllowsLocalNetworking` как boolean `false`.
- `swift test --filter AdaptiveLayoutTests` не является валидным runner для этого monorepo на macOS: SwiftPM также собирает UIKit-only `ShareExtensionUI` и останавливается на `no such module UIKit`; Xcode iOS `build-for-testing` используется как compile gate.

### Gates после реализации

```bash
bash scripts/policy-check.sh
bash scripts/lint-i18n.sh
bash scripts/audit-ui-layout.sh specs/062-mac-ipad-layout

SIM_ID="$(bash scripts/resolve-simulator.sh)"
xcodebuild -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  build
xcodebuild -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  test

xcodebuild -scheme RecipeScalerMac \
  -destination 'platform=macOS' \
  build
```

Expected evidence: every command exits `0`; unit/UI tests prove the positive invariants above; `audit-ui-layout.sh` is at least `STATIC PASS`, and final UI acceptance additionally has matching human acceptance. Web parity is checked against existing `main-nav`, `AdaptiveRow` and `DesktopScrollableRow` tests rather than by changing the web repository in this feature.

## Rollback / maintenance

- До начала реализации можно безопасно откатить WIP одним revert-коммитом относительно `master`; не использовать destructive reset.
- Mac target должен оставаться отдельным commit/phase, чтобы при регрессии platform probe можно было оставить iPad regular без частичного Mac runtime.
- UserDefaults keys и route contract считаются публичными внутри native app: не переименовывать их без migration/fixture.
- Временные platform allowlists допустимы только с owner, причиной и условием удаления; stale WIP files не добавлять в allowlist молча.
- После принятия плана обновить managed Spec Kit section в `AGENTS.md` на canonical feature path.
