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
| `RecipeScalerNative/App/AppContainer.swift` | Изменён: вызывать health-check до `sync.start` в `bootstrap(userId:)` |

### Downstream consumers

- [x] **SwiftUI views** — `ContentView` (`isAuthenticated`, `effectiveUserId`)
      при `isAuthenticated == false` показывает `AuthView` автоматически.
- [x] **Cross-process consumers** — `SharedAuthStore.clear()` инвалидирует
      userId для extensions/watch; `WatchCredentialsBridge.shared.purge()`
      уведомит watch.
- [x] **Sync boundaries** — health-check идёт **до** `sync.start`, поэтому
      socket ещё не поднят; race отсутствует.
- [x] **Persisted state** — Keychain (seed phrase), SharedAuthStore (userId,
      token) — оба чистятся теми же API, что и `logout()` (без server call).
- [x] **Tests / verify-скрипты** — добавить `AuthServiceStaleSessionTests`.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| Health-check 404 | `SharedAuthStore.userId == nil` после вызова | `AuthServiceStaleSessionTests` |
| Health-check 5xx | `SharedAuthStore.userId` сохранён | `AuthServiceStaleSessionTests` |
| Health-check timeout | `SharedAuthStore.userId` сохранён | `AuthServiceStaleSessionTests` |
| DEBUG simulator | Health-check не вызывается (пропущен) | `AuthServiceStaleSessionTests` |

### Note

Используем существующий `APIClient.shared.requestJSON` с коротким timeout
через `URLSession.configuration.timeoutIntervalForRequest = 5`. Это означает
отдельный URL session или copy конфигурации; в `AppURLSession.shared` можно
временно поднять timeout, либо сделать health-check через
`performAuthRequest` (там используется `AppURLSession.shared`).

Вариант **B (выбран)**: добавить `checkUserExists` в `AccountAPI` через
`APIClient.shared.requestJSON`, перехватить `APIError.httpError(404)` и
вернуть `.userMissing`. Для 5xx вернуть `.transient`. Для 401 вернуть
`.unauthorized`. Для network error / timeout — `.transient`. На уровне
`AuthService` только `.userMissing` / `.unauthorized` триггерят wipe.

Race с DEBUG auto-login: `ContentView.effectiveUserId` на симуляторе возвращает
`debugUserId`, минуя Keychain. Health-check должен detecting DEBUG simulator
через `#if targetEnvironment(simulator)` + `XCTestConfigurationFilePath` gate.

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
  все green
- `bash scripts/lint-i18n.sh` — все green
- (verify-ui-smoke не нужен — UI не меняется, AuthView уже существует)
