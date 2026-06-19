# Spec: Architecture — composition root + @Observable миграция (#27, #28)

**Date**: 2026-06-19 | **Status**: in-progress

## Обзор

Две архитектурные очистки из review-kilo:

- **#27** — нет composition root с DI; 12 синглтонов `.shared` тянутся друг в друга; скрытое связывание внутри `YjsSyncService.start`.
- **#28** — смешаны `ObservableObject` и `@Observable` макрос в слое сервисов/view-models; per-property observation потерян на самом большом state-holder.

Один PR. После remediation в проекте единая точка construction (AppContainer), явный dependency graph, единый observation-фреймворк.

## Контекст (по данным subagent-исследования)

### Composition root (нынешнее состояние)

- Реальный composition root — [RecipeScalerNative/ContentView.swift:21-54](../../RecipeScalerNative/ContentView.swift), не `@main App`.
- В `ContentView.init` создаются только 4 сервиса: `YrsDatabase` → `YDocStore`/`RemindersMapStore` → `YjsSyncService`/`RemindersSyncService`/`SpotlightIndexer`.
- `AuthService`, `TimerManager` и пр. — глобальные `.shared` singletons, не создаются в composition root.
- **`YjsSyncService` — НЕ singleton** (исправление неточности ревью): создаётся в `ContentView.init`, пробрасывается в 20 view'ов через `@StateObject` + `@EnvironmentObject`.
- Скрытое связывание в [YjsSyncService.start](../../RecipeScalerNative/Services/YjsSync/YjsSyncService.swift) (строки 856-884):
  - `APIClient.shared.configure(userId:)` — дублируется из `ContentView.init:45`.
  - `TimerSyncService.shared.configure(...)` + циклический callback `TimerSyncService.shared.sendTimerEvent = { [weak self] ... }`.
  - `PushRegistrationService.shared.registerIfNeeded()`.
  - `ImageCacheService.shared` observers install.

### Singletons `.shared` (12 в production)

`APIClient`, `AuthService`, `TimerManager`, `TimerSyncService`, `TimerLiveActivityCoordinator`, `PushRegistrationService`, `PushScheduleService`, `ImageCacheService`, `PublicImageCacheService`, `RecipeImageService`, `YjsMergeHelper`, `AssistantRecipeContext`, `DeepLinkRouter`.

### OS-фасады (НЕ убираем `.shared`)

| Type | Причина |
|------|---------|
| `SharedAuthStore` (enum) | Keychain access group, cross-process IPC main app ↔ Share/Action |
| `AppGroup` (enum) | App Group id literal + UserDefaults suite helper |
| `TimerSnapshotStore` (enum) | App Group UserDefaults для HomeWidget timeline |
| `Config` (struct literals) | `baseURL`, `wsBaseURL` — без instance state |
| `APIClient.shared` | Process-local default для extensions (`ShareView` + `RecipeImportAPI`); каждый процесс конфигурит свой инстанс |

### Observable patterns (нынешнее состояние)

- **7 классов на `ObservableObject`** (подлежат миграции):
  - `YjsSyncService` (15 `@Published`, файл 2475 LOC) — главный state-holder.
  - `DescriptionEditorBridge` (6 `@Published`).
  - `DescriptionEditorChromeState` (3 `@Published`).
  - `SpotlightIndexer` (0 `@Published` — vestigial).
  - `RecipeListViewModel` (2 `@Published`, не `final`).
  - `RemindersSyncService` (2 `@Published`).
  - `APIClient` (0 `@Published` — vestigial conformance).
- **9 классов уже на `@Observable`** (без изменений): `AuthService`, `TimerManager`, `DeepLinkRouter`, `AssistantRecipeContext`, `RecipeEditViewModel`, `RecipeListSearchStore`, `AccountSettingsViewModel`, `DiscoverSearchStore`, `AssistantVoiceRecorder`.
- **20 `@EnvironmentObject` sites** (19 потребляют `YjsSyncService`, 1 — `RemindersSyncService`).
- **4 `@StateObject` + 4 `@ObservedObject`** для DescriptionEditorBridge/ChromeState.
- **Mix на одном struct**: `YDocRecipeDetailView` (YjsSyncService ObservableObject + DescriptionEditorChromeState ObservableObject + RecipeEditViewModel @Observable) — форсит одновременно `objectWillChange` и Observation tracking.

## Цели

1. Ввести `AppContainer` (`@MainActor @Observable final class`) как single source of truth для всех 12 singleton-сервисов.
2. Создавать `AppContainer` в `RecipeScalerNativeApp.init`, провайдить в `WindowGroup` через `@Environment(AppContainer.self)`.
3. `ContentView.init()` становится тонким view, читающим контейнер из environment.
4. Все 19 view'ов с `@EnvironmentObject YjsSyncService` мигрируют на `@Environment(YjsSyncService.self)`.
5. Все 7 `ObservableObject` классов мигрируют на `@Observable` macro (или теряют vestigial conformance — для `APIClient`).
6. Циклический callback `TimerSyncService.sendTimerEvent` выносится в `TimerEventBridge`, owned AppContainer'ом.
7. Скрытое связывание внутри `YjsSyncService.start` переезжает в `AppContainer.bootstrap()`.
8. Extension boundary остаётся нетронутым (Share/Action/HomeWidget/TimerLiveActivity не требуют правок).

## Non-goals (явно вне scope)

- **#9** `YjsSyncService` god-object (2411+ строк) — отдельный spec.
- **#10** `DocumentManager` god-object (1603 строки) — отдельный spec.
- **#46** sync-error classification по строковым паттернам.
- **#47** dead-code local-update-bridge.
- **#48** unbounded description-editor session registry.
- **#49** sprawl reconnect/watchdog таймеров (5 перекрывающихся state-машин).
- Удаление `.shared` с OS-фасадов (`SharedAuthStore`, `AppGroup`, `TimerSnapshotStore`, `Config`, `APIClient`).
- Удаление `YjsMergeHelper` WKWebView (#6) — отдельный perf spec.
- Рефакторинг `RecipeScalerCore` (всё, что в Core, остаётся).

## Риски

| Риск | Решение |
|------|---------|
| Mix на `YDocRecipeDetailView` ломает билд при миграции YjsSyncService | Переписать в одном коммите `@EnvironmentObject` → `@Environment` для всех 19 YjsSyncService consumers |
| Циклический callback `TimerSyncService.sendTimerEvent` | Вынести в `TimerEventBridge` (struct, owned AppContainer); использовать `[weak]` ссылки на `YjsSyncService` и `TimerSyncService` |
| Tests используют `.shared` напрямую | Найти через `rg '\.shared' RecipeScalerNativeTests/`, обновить на `AppContainer()` или явный `init` |
| Extension target breaks (Share/Action/HomeWidget/TimerLiveActivity) | Не трогать `APIClient.shared` + `SharedAuthStore` + `AppGroup` + `TimerSnapshotStore`; они не ссылаются на `.shared` production-сервисов |
| `RecipeListViewModel` не `final` | Сделать `final` одновременно с миграцией на `@Observable` |
| `TimerManager` смешивает `@Observable` с `NSObject` | Оставить как есть (legacy `NSObject` для `NSBackgroundActivityScheduler`); миграция не нужна |
| `YjsMergeHelper` `NSObject + WKNavigationDelegate` | Мигрировать только `static let shared` → DI; observable не трогать |
| Большие размеры файлов `YjsSyncService` (2475 LOC) | Не рефакторить god-object (это #9); только observable macro + убрать side-effects из `start()` |
| Live Activity metadata lookup (static closure slot) | `TimerLiveActivityMetadataProvider.recipeNameLookup` — process-global mutable slot, owned контейнером через `bootstrap()` |
| `fatalError` на corrupted SwiftData ([RecipeScalerNativeApp.swift:83](../../RecipeScalerNative/RecipeScalerNativeApp.swift)) | Сохранить in-memory fallback логику для `YrsDatabase` (не в scope #68) |

## Layout

UI не меняется. Layout-аудит **не требуется** — бэкенд/сервисный слой + property-wrapper замена в views, без изменений в визуальной вёрстке.

## Verify

```bash
xcodebuild build -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
xcodebuild build -scheme ShareExtension -destination 'generic/platform=iOS Simulator'
xcodebuild build -scheme ActionExtension -destination 'generic/platform=iOS Simulator'
xcodebuild test -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
```

По `.agents/skills/fix-until-green/SKILL.md`: до 5 итераций fix → build → test. Верdict `VERIFIED` / `NOT VERIFIED` / `INCONCLUSIVE` с evidence (команда + exit code).
