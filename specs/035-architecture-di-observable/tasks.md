# Tasks: Architecture — composition root + @Observable миграция

## Phase A — Spec artefacts

- [x] Создать `specs/035-architecture-di-observable/spec.md`
- [x] Создать `specs/035-architecture-di-observable/plan.md`
- [x] Создать `specs/035-architecture-di-observable/tasks.md`
- [x] Создать `specs/035-architecture-di-observable/design.md`

## Phase B — AppContainer (#27 core)

### B1-B2. Создать AppContainer + Environment

- [x] Создать `RecipeScalerNative/App/AppContainer.swift`
- [x] Создать `RecipeScalerNative/App/AppEnvironment.swift` (EnvironmentKey extensions)
- [x] Зарегистрировать оба файла в `project.pbxproj` main app target

### B3. Перенести wiring в AppContainer.bootstrap()

- [x] Создать `RecipeScalerNative/App/TimerEventBridge.swift`
- [x] Перенести `APIClient.shared.configure(userId:)` вызовы (дедуплицировать)
- [x] Перенести `TimerSyncService.configure(...)` + убрать циклический callback
- [x] Перенести image-cache observers install
- [x] Перенести `TimerLiveActivityMetadataProvider.recipeNameLookup` setup

### B4-B5. ContentView + App init

- [x] Упростить `ContentView.swift` — удалить ручное construction
- [x] Обновить `RecipeScalerNativeApp.swift` — создавать AppContainer, провайдить через environment
- [x] На `task` вызвать `await container.bootstrap(userId:)`

### B6. Удалить .shared с 12 синглтонов

- [x] Все 12 сервисов: `.shared` → shim, форвардящий в `AppContainer.shared.<service>` (fallback `Standalone` для pre-bootstrap / AppIntents)
- [x] Явные `init(...)` с зависимостями в `AppContainer.init`

## Phase C — Миграция на @Observable (#28)

### C1. YjsSyncService

- [x] `@Observable` + 15 `@Published` → `private(set) var`
- [x] 19 view'ов: `@EnvironmentObject` → `@Environment(YjsSyncService.self)`

### C2. RemindersSyncService

- [x] `@Observable` + `@Environment(RemindersSyncService.self)` в `AccountView`

### C3. SpotlightIndexer

- [x] `@Observable` (vestigial conformance)

### C4. RecipeListViewModel

- [x] `final` + `@Observable`

### C5. DescriptionEditorBridge

- [x] `@Observable` + `@State`/`@Bindable` consumers

### C6. DescriptionEditorChromeState

- [x] `@Observable` + `@State`/`@Bindable` consumers

### C7. APIClient

- [x] Убрать vestigial `: ObservableObject` (`.shared` оставить)

## Phase D — Cleanup

### D1. Тесты

- [x] `RecipeScalerNativeTests/AppContainerTests.swift`
- [x] `RecipeScalerNativeTests/ObservableMigrationTests.swift`
- [x] Зарегистрированы в `project.pbxproj` test target

### D2. Документация

- [x] `docs/ARCHITECTURE.md` — секция «Composition Root / DI»
- [x] `AGENTS.md` — упомянуть AppContainer
- [x] `review-kilo-glm-5.2-recipe-scaler-native.md` — #27, #28 remediated
- [x] View-layer: `AppShellView`, `AccountView`, `AuthView`, `AssistantComposer`, `YDocRecipeDetailView`, `DiscoverRecipeView` — `@Environment` вместо `.shared` где контейнер доступен

## Phase E — Fix-until-green

- [x] `xcodebuild build -scheme RecipeScalerNative` green
- [x] `xcodebuild build -scheme ShareExtension` green
- [x] `xcodebuild build -scheme ActionExtension` green
- [x] `xcodebuild test-without-building` — `AppContainerTests` (5) + `ObservableMigrationTests` (3): **0.7s execution**, ~36s wall (simulator boot)
- [ ] Полный `xcodebuild test` — не блокер #27/#28; есть pre-existing failures (`LocalizationConsistencyTests` stale keys `recipe.import.folder-*`, flaky `AssistantPendingActionTests` fatal `try!`)

**Рекомендуемый цикл** (см. `docs/AGENT-WORKFLOW.md`): `build-for-testing` → `test-without-building`. Не использовать `| tail -N` — буферизует весь вывод до конца прогона и создаёт иллюзию зависания.
