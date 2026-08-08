# Plan: Architecture — composition root + @Observable миграция (#27, #28)

**Date**: 2026-06-19 | **Spec**: [spec.md](./spec.md)

## Очерёдность

1. **Phase B** (#27 core) — AppContainer + Environment wiring; синглтоны теряют `.shared`. Без миграции observable-фреймворка.
2. **Phase C** (#28) — миграция на `@Observable`; каждый класс отдельно, синхронно с его consumer'ами.
3. **Phase D** — cleanup: тесты + docs.

Между фазами проект **компилируется и проходит тесты**. Каждый коммит внутри фазы — зелёный.

## Phase B — AppContainer

### B1. Создать `RecipeScalerNative/App/AppContainer.swift`

`@MainActor @Observable final class`, владеющий всеми 12 сервисами. Construction graph строится в `init() throws` в порядке зависимостей. `bootstrap(userId:) async` выполняет wiring, который раньше жил в `YjsSyncService.start`.

### B2. Создать `RecipeScalerNative/App/AppEnvironment.swift`

`EnvironmentKey` + `EnvironmentValues` extensions для инъекции контейнера и каждого Observable-сервиса, который нужен view'ам напрямую: `YjsSyncService`, `RemindersSyncService`, `SpotlightIndexer`, `AuthService`, `TimerManager`, `DeepLinkRouter`, `AssistantRecipeContext`.

### B3. Перенести wiring из [YjsSyncService.start](../../RecipeScalerNative/Services/YjsSync/YjsSyncService.swift) (строки 856-884) в `AppContainer.bootstrap()`

Включая циклический callback `TimerSyncService.sendTimerEvent`. Создать `RecipeScalerNative/App/TimerEventBridge.swift` (опционально), который связывает `TimerSyncService` и `YjsSyncService` через weak-refs.

### B4. Упростить [ContentView.swift](../../RecipeScalerNative/ContentView.swift)

- Удалить ручное создание `YrsDatabase`/`YDocStore`/`RemindersMapStore`/`YjsSyncService`/`RemindersSyncService`/`SpotlightIndexer` из `init()`.
- `init()` становится trivial (или удаляется).
- `body` читает `@Environment(AppContainer.self)` и пробрасывает подсервисы через `.environment(...)`.

### B5. Обновить [RecipeScalerNativeApp.swift](../../RecipeScalerNative/RecipeScalerNativeApp.swift)

- В `App.init` создавать `AppContainer` (с `fatalError` fallback как сейчас для `YrsDatabase`).
- Сохранять в `@State` (Observable).
- Провайдить в `WindowGroup` через `.environment(container)`.
- На `task` вызывать `await container.bootstrap(userId:)`.

### B6. Удалить `.shared` с 12 синглтонов

| Type | Новый `init` |
|------|--------------|
| `AuthService` | `init(apiClient: APIClient = .shared)` |
| `TimerManager` | `init(timerSync:, liveActivity:, pushSchedule:, modelContext:)` |
| `TimerSyncService` | `init(apiClient:, timerManager:)` — убрать `weak var timerManager` assignment в `configure` |
| `TimerLiveActivityCoordinator` | `init()` (без `.shared`) |
| `PushRegistrationService` | `init(auth:, apiClient:)` |
| `PushScheduleService` | `init(apiClient:)` |
| `ImageCacheService` | `init()` (без `.shared`) |
| `PublicImageCacheService` | `init()` (без `.shared`) |
| `RecipeImageService` | `init(imageCache:, publicImageCache:, apiClient:)` |
| `YjsMergeHelper` | `init()` (без `.shared`) |
| `AssistantRecipeContext` | `init()` (без `.shared`) |
| `DeepLinkRouter` | `init()` (без `.shared`) |

## Phase C — Миграция на @Observable

### C1. `YjsSyncService` → `@Observable`

- `@MainActor final class YjsSyncService: ObservableObject` → `@MainActor @Observable final class YjsSyncService`.
- 15 `@Published private(set) var X` → `private(set) var X`.
- `syncErrorMessage` (строка 31, external writable) → обычный `var`.
- 19 view'ов: `@EnvironmentObject var sync: YjsSyncService` → `@Environment(YjsSyncService.self) var sync`.
- `ContentView` провайдинг: `.environmentObject(sync)` → `.environment(sync)`.
- `DescriptionWireExportHost` (`@ObservedObject var syncService`) → `@Bindable var syncService`.

### C2. `RemindersSyncService` → `@Observable`

- 2 `@Published` (`authorizationStatus`, `availableLists`) → обычные `private(set) var`.
- 1 view: `AccountView.swift:17` → `@Environment(RemindersSyncService.self)`.

### C3. `SpotlightIndexer` → `@Observable`

- 0 `@Published` (vestigial) — просто заменить `: ObservableObject` → `@Observable`.

### C4. `RecipeListViewModel` → `@Observable`

- 2 `@Published` (`isLoading`, `errorMessage`).
- Сделать класс `final`.
- Найти все `@StateObject`/`@ObservedObject` этого типа и переписать на `@State`/`@Bindable`.

### C5. `DescriptionEditorBridge` → `@Observable`

- 6 `@Published` (`phase`, `isFocused`, `contentHeight`, `selectionState`, `lastNodeClick`, `nodeClickSequence`).
- 3 view'а `@StateObject` + 2 `@ObservedObject` → `@State`/`@Bindable`.

### C6. `DescriptionEditorChromeState` → `@Observable`

- 3 `@Published` (`isFocused`, `isEditorReady`, `suppressFormattingBar`).
- 1 `@StateObject` + 1 `@ObservedObject` → `@State`/`@Bindable`.

### C7. `APIClient` — убрать vestigial `ObservableObject`

- 0 `@Published` — удалить `: ObservableObject`.
- `.shared` оставить (process-local default для extensions).

## Phase D — Cleanup

### D1. Тесты

- `rg '\.shared' RecipeScalerNativeTests/` — обновить каждый call site на `AppContainer()` или явный `init`.
- Создать `RecipeScalerNativeTests/AppContainerTests.swift` — construction graph + доступность сервисов.
- Создать `RecipeScalerNativeTests/ObservableMigrationTests.swift` — assertion что все 7 ключевых типов теперь `@Observable` (через `Mirror` или compile-time check).

### D2. Документация

- [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md) — новая секция «Composition Root / DI» с mermaid.
- [AGENTS.md](../../AGENTS.md) — упомянуть AppContainer как single source of truth.
- [review-kilo-glm-5.2-recipe-scaler-native.md](../../review-kilo-glm-5.2-recipe-scaler-native.md) — отметить #27, #28 как remediated.

## Phase E — Fix-until-green

```bash
xcodebuild build -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5'
xcodebuild build -scheme ShareExtension -destination 'generic/platform=iOS Simulator'
xcodebuild build -scheme ActionExtension -destination 'generic/platform=iOS Simulator'
xcodebuild test -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5'
```

## Оценка объёма

- ~50 production файлов изменено/создано
- ~10 test файлов обновлено
- ~5 spec/docs файлов
- 1 commit (PR), fix-until-green по 3 scheme build + full test suite
