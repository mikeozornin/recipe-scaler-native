# Tasks: Auth stale-session recovery + sync_error.truncated_collection

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Generated 2026-07-16. Задачи зависимостями упорядочены.

---

## Phase 1: Typed sync error code

- [ ] T1.1 Добавить case `truncatedCollection = "sync.error.truncated-collection"` в `SyncErrorCode` (Swift)
- [ ] T1.2 Добавить legacy message match для "truncated collection" в `SyncErrorCode.from`
- [ ] T1.3 Добавить ветку `.truncatedCollection` в `handleSyncError` → `reloadCollectionFromServer()` без установки `syncErrorMessage`
- [ ] T1.4 Создать `RecipeScalerNativeTests/Services/SyncErrorCodeTests.swift` с тестом `from(code:)` для нового case

## Phase 2: Auth stale-session health check

- [ ] T2.1 В `AccountAPI` добавить `enum UserExistsResult { case exists, userMissing, unauthorized, transient }` и метод `checkUserExists() async -> UserExistsResult` (перехват APIError.httpError(404) и (401), 5xx → transient, network/timeout → transient)
- [ ] T2.2 Ввести протокол `UserSettingsProbing` с методом `checkUserExists() async -> UserExistsResult`; `AccountAPI` соответствует по умолчанию
- [ ] T2.3 В `AuthService` добавить свойство `userSettingsProbe: UserSettingsProbing` (default = AccountAPI), для тест-инъекции
- [ ] T2.4 Добавить метод `performStaleSessionHealthCheck() async` — вызывает `userSettingsProbe.checkUserExists()`, при `.userMissing`/`.unauthorized` → `wipeLocalSession()`
- [ ] T2.5 Добавить приватный метод `wipeLocalSession()` — повторяет `logout()` без server call и без throw (Keychain + SharedAuthStore.clear + WatchCredentialsBridge.purge + reset published props + APIClient.reset)
- [ ] T2.6 Вызывать `performStaleSessionHealthCheck()` из `restoreAuthenticationState` (через `Task`) **только при наличии сохранённого userId и только вне XCTest/simulator-debug**
- [ ] T2.7 В `AppContainer.bootstrap(userId:)` добавить await `auth.performStaleSessionHealthCheck()` **до** шага 5 (`sync.start`); при возврате `isAuthenticated == false` — ранний return без старта sync

## Phase 3: i18n

- [ ] T3.1 Добавить ключ `sync.error.truncated-collection` в `Localizable.xcstrings` с ru и en значениями

## Phase 4: Tests

- [ ] T4.1 Создать `RecipeScalerNativeTests/Services/AuthServiceStaleSessionTests.swift` с mock probe
- [ ] T4.2 Тест: health-check `.userMissing` → `isAuthenticated == false`, `SharedAuthStore.userId == nil`, Keychain seed удалён
- [ ] T4.3 Тест: health-check `.unauthorized` → тот же wipe
- [ ] T4.4 Тест: health-check `.transient` → `isAuthenticated == true`, состояние сохранено
- [ ] T4.5 Тест: health-check `.exists` → `isAuthenticated == true`, состояние сохранено

## Phase 5: Build & verify

- [ ] T5.1 `xcodebuild build` — green
- [ ] T5.2 `xcodebuild test` — green для новых тест-классов
- [ ] T5.3 `bash scripts/lint-i18n.sh` — green
