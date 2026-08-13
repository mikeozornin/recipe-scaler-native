# Plan: Auth stale-session recovery + sync_error.truncated_collection

**Date**: 2026-07-16 | **Spec**: [spec.md](./spec.md)

> План реализации: health-check `/api/settings` на cold start с wipe при 404,
> и добавление typed case `truncated_collection` в `SyncErrorCode`.

---

## Очерёдность

1. **`SyncErrorCode.truncatedCollection`** — нет зависимостей, минимальная
   правка, компилятор exhaustive switch подсветит все call sites.
2. **Health-check в `AuthService`** — ядро спеки, зависит от (1) только в том
   смысле, что меняем один и тот же слой `Services/`.
3. **i18n strings** — после (1) и (2), чтобы знать финальный набор ключей.
4. **Tests** — после (1)-(3).

> Шаги 1 и 2 можно делать в параллели, но компилироваться будут вместе.

---

## Шаг 1. SyncErrorCode.truncatedCollection

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/YjsSync/SyncErrorCode.swift` | Изменён: добавить case + legacyMessage match |
| `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` | Изменён: добавить ветку в `handleSyncError` |

### Downstream consumers

- [x] **SwiftUI views** — `syncErrorMessage` (`YDocRecipeDetailView.swift:494`)
      читается через `.onChange`. Для `truncatedCollection` мы **не**
      устанавливаем `syncErrorMessage` → пользователь не видит alert.
- [x] **Cross-process consumers** — sync_error чисто локальный, не уходит в
      extensions/watch.
- [x] **Sync boundaries** — wire event `sync_error.code: truncated_collection`
      уже определён в web `specs/shared/sync-protocol.md` (commit 2c7e081f).
- [x] **Persisted state** — не трогаем; unsynced-флаг НЕ выставляется.
- [x] **Tests / verify-скрипты** — нужно добавить тест `SyncErrorCodeTests`.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| `SyncErrorCode.from(code: "sync.error.truncated-collection")` | == `.truncatedCollection` | `SyncErrorCodeTests` |
| `handleSyncError(.truncatedCollection, _, nil)` | вызывает `reloadCollectionFromServer()`, не выставляет `syncErrorMessage` | `YjsSyncServiceTruncatedCollectionTests` |

### Note

Берём формат rawValue `"sync.error.truncated-collection"` — соответствует
конвенции остальных cases (kebab-case после `sync.error.`). Имя server-side
кода остаётся `'truncated_collection'` (snake_case на wire, как в
`yjs-service.ts:156`), но typed Swift enum маппит на dot-key.

Решение о том, что мы не показываем user-facing alert для `truncatedCollection`
(используем `reloadCollectionFromServer`), принято потому что нативка на legacy
`load_document`, и reload коллекции автоматически восстановит состояние без
потери данных. Локализованная строка добавляется на случай будущего UI.

---

## Шаг 2. Health-check на cold start

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/AuthService.swift` | Изменён: добавить `performStaleSessionHealthCheck()` + вызвать из `restoreAuthenticationState` |
| `RecipeScalerNative/Services/AccountAPI.swift` | Изменён: добавить `checkUserExists() async -> UserExistsResult` (без throws, возвращает enum) |
| `RecipeScalerNative/App/AppContainer.swift` | Изменён: `scheduleStaleSessionHealthCheckIfNeeded` в фоне из `bootstrap`; не await до `sync.start` |

### Downstream consumers

- [x] **SwiftUI views** — `ContentView` (`isAuthenticated`, `effectiveUserId`)
      при `isAuthenticated == false` показывает `AuthView` автоматически.
      `RecipeListView` / `CollectionsRootView` читают `isLocalDataLoaded`,
      который выставляется `loadLocalSnapshots()`, не probe.
- [x] **Cross-process consumers** — `SharedAuthStore.clear()` инвалидирует
      userId для extensions/watch; `WatchCredentialsBridge.shared.purge()`
      уведомит watch.
- [x] **Sync boundaries** — probe параллелен `sync.start`. При 404/401 wipe
      зовёт `performInvalidationTeardown` (stop socket). Transient — сокет
      может ретраить в офлайне, список уже из SQLite.
- [x] **Persisted state** — Keychain (seed phrase), SharedAuthStore (userId,
      token) — оба чистятся теми же API, что и `logout()` (без server call).
- [x] **Tests / verify-скрипты** — `AuthServiceStaleSessionTests`,
      `AppContainerTests` (schedule не блокирует; фоновый 404 → wipe).

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| Health-check 404 | `SharedAuthStore.userId == nil` после вызова | `AuthServiceStaleSessionTests` |
| Health-check 5xx | `SharedAuthStore.userId` сохранён | `AuthServiceStaleSessionTests` |
| Schedule не ждёт probe | сессия жива, пока continuation не resume | `AppContainerTests` |
| Фоновый `.userMissing` | wipe после resume | `AppContainerTests` |

### Note

Используем `AccountAPI.checkUserExists` через `APIClient.shared.requestJSON`
(`URLSession.shared`). 404 → `.userMissing`, 401/403 → `.unauthorized`,
5xx / network / timeout → `.transient`. Wipe только на `.userMissing` /
`.unauthorized`. Probe **не** стоит на критическом пути UI: `bootstrap`
планирует Task и сразу идёт в `sync.start` → `loadLocalSnapshots()`.

DEBUG simulator: probe выполняется; при wipe (не XCTest) — re-inject
auto-login + повторный `bootstrap`. E2E override выставляет
`didPerformStaleSessionHealthCheck` и skip.

### Async lifecycle (probe)

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|----------|-------------------|---------------------|-------------------|-----------------------|
| `staleSessionHealthCheckTask` | `expectedUserId` | `Task.isCancelled`; если ещё authenticated — `auth.userId == expectedUserId` | `resetBootstrapAfterLogout` / `stopForLogout` | `AppContainerTests` (hanging probe + late wipe) |

---

## Шаг 3. i18n strings

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменён: добавить `sync.error.truncated-collection` |

### Downstream consumers

- [x] **SwiftUI views** — не используется напрямую сейчас (см. шаг 1 Note).
- [x] **Tests / verify-скрипты** — `scripts/lint-i18n.sh` должен пройти.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| `Bundle.currentLocalizedString("sync.error.truncated-collection")` | не возвращает key как есть, есть ru + en значения | `scripts/lint-i18n.sh` |

---

## Шаг 4. Tests

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNativeTests/Services/SyncErrorCodeTests.swift` | Создан |
| `RecipeScalerNativeTests/Services/AuthServiceStaleSessionTests.swift` | Создан |

### Downstream consumers

- [x] Тесты изолированы, не влияют на существующие.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| Тест на `truncatedCollection` | `SyncErrorCode.from(code: "sync.error.truncated-collection") == .truncatedCollection` | `SyncErrorCodeTests` |
| Тест на 404 wipe | После `performStaleSessionHealthCheck` с замокированным 404 — `isAuthenticated == false`, Keychain пустой | `AuthServiceStaleSessionTests` |
| Тест на 5xx keep | После health-check с замокированным 503 — `isAuthenticated == true` | `AuthServiceStaleSessionTests` |

### Note

Для `AuthServiceStaleSessionTests` потребуется прототипировать
`AccountAPI.checkUserExists` через протокол, чтобы замокировать в тестах.
Минимальный объём — протокол `UserSettingsProbing` с одним методом.
Альтернатива: `@testable import` + injection через static-флаг теста.
Выбираем протокол: чище, и не ломает существующую инициализацию.

---

## Verify

- `xcodebuild build` — scheme `RecipeScalerNative`, все green
- `xcodebuild test` — `SyncErrorCodeTests`, `AuthServiceStaleSessionTests`,
  `AppContainerTests`, все green
- `bash scripts/lint-i18n.sh` — все green
- (verify-ui-smoke не нужен — UI не меняется, AuthView уже существует)
