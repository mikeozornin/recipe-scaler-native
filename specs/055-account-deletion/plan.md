# Plan: Удаление аккаунта (native) + Phase R runtime recovery

**Date**: 2026-08-01 | **Spec**: [spec.md](./spec.md)

> Реализация исходной spec 055 (UI + `AuthService.deleteAccount`) уже в master.
> Этот план покрывает **Phase R** — runtime-реакцию на server-side удаление
> аккаунта (баг: при удалении из веба натив висит в «оффлайн» до перезапуска).

---

## Очерёдность

1. **R1 — `AuthRevocationConstants`** — нет зависимостей, нужно всем остальным.
2. **R2 — `AuthService.handleAccountDeleted` + re-entry guard** (после R1).
3. **R3 — `AuthService.handleDeviceTokenInvalid`** (после R2, использует
   существующий `exchangeSeedForToken`).
4. **R4 — `APIClient.shared` 401-interceptor** (после R3, делегирует в R3).
5. **R5 — `YjsSyncService.auth_error` handler + closure injection** (после R2,
   в параллель с R3/R4).
6. **R6 — Unit-тесты** (после R2–R5).
7. **R7 — E2E тест** (после R6).
8. **Verify** — build + test green.

---

## R1 — AuthRevocationConstants

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerCore/Networking/AuthRevocationConstants.swift` | Создан |

### Downstream consumers

- [x] **SwiftUI views** — не читают (константа для сервисов).
- [x] **Cross-process consumers** — extensions используют `RecipeScalerCore`,
  видят константу (safe — read-only).
- [x] **Sync boundaries** — нет.
- [x] **Persisted state** — нет.
- [x] **Tests / verify-скрипты** — R6 использует константу в ассертах.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| `AuthRevocationConstants.accountDeletedSocketMessage` | `== "Account deleted"` (parity с web `AUTH_ACCOUNT_DELETED_SOCKET_MESSAGE`) | `AuthSessionInvalidationTests` |

### Note

Паритет с `recipe-scaler-web/recipe-scaler/src/types/auth-api.ts`
(`AUTH_ACCOUNT_DELETED_SOCKET_MESSAGE = "Account deleted"`).

---

## R2 — AuthService.handleAccountDeleted + re-entry guard

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/AuthService.swift` | Изменён: `wipeLocalSession(reason:)`, `handleAccountDeleted(reason:)`, `isHandlingAccountInvalidation`, `AccountInvalidationReason` enum |

### Downstream consumers

- [x] **SwiftUI views** — `ContentView.onChange(of: authService?.isAuthenticated)`
  реагирует на flip → `clearSessionForLogout` + `stopForLogout`.
- [x] **Cross-process consumers** — `WatchCredentialsBridge.purge()`,
  `RecipeSnapshotStore.clear` (добавить), Live Activity invalidate (добавить).
- [x] **Sync boundaries** — socket teardown в `clearSessionForLogout` уже есть.
- [x] **Persisted state** — Keychain seed, `SharedAuthStore.clear()`,
  `AppContainer.featureAdoption.clearForLogout()`.
- [x] **Tests** — R6.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| `handleAccountDeleted(.socketSignal)` | `isAuthenticated == false`, `userId == nil`, Keychain seed пуст, `SharedAuthStore` пуст | `AuthSessionInvalidationTests.test_socket_account_deleted_wipes` |
| Двойной вызов `handleAccountDeleted` | wipe выполнен ровно 1 раз | `AuthSessionInvalidationTests.test_double_signal_single_wipe` |

### Note

- Re-entry guard — простой `private var isHandlingAccountInvalidation = false`
  на `@MainActor AuthService`. Сбрасывается после завершения wipe.
- `wipeLocalSession(reason:)` логирует `AppLog.info(.app, "session_wiped", data: ["reason": ...])`.
- Teardown (`clearSessionForLogout` + `stopForLogout`) — через weak ref на
  `AppContainer.shared`, чтобы не циклить.

---

## R3 — AuthService.handleDeviceTokenInvalid (seed exchange recovery)

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/AuthService.swift` | Изменён: `handleDeviceTokenInvalid() async`, `SessionWipeReason.lightRevoke` |

### Downstream consumers

- [x] **APIClient unauthorizedHandler** — вызывает этот метод (R4).
- [x] **SwiftUI views** — `ContentView.onChange(isAuthenticated)` для light-revoke.
- [x] **Tests** — R6.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| REST 401 + exchange 404 | `isAuthenticated == false`, wipe вызван, `stopForLogout` вызван | `test_rest_401_exchange_404_wipes` |
| REST 401 + exchange success | `isAuthenticated == true`, новый токен применён, wipe **не** вызван | `test_rest_401_exchange_success_keeps_session` |
| REST 401 + exchange network failure | `isAuthenticated == false`, wipe вызван, `stopForLogout` **не** вызван | `test_rest_401_exchange_network_light_revoke` |

### Note

- Detecting "User not found" в ответе exchange: сервер возвращает 404 с
  `error: "User not found"` или похожим сообщением. Проверяем и статус, и
  case-insensitive contains "not found" в message (паритет с веб-контрактом).
- Light revoke путь: `wipeLocalSession(reason: .lightRevoke)` без вызова
  `stopForLogout` — пользователь может пере-логиниться, локальные данные
  остаются для возможного recovery.

---

## R4 — APIClient.shared centralized 401 interceptor

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerCore/Networking/APIClient.swift` | Изменён: `unauthorizedHandler: (@Sendable () async -> Void)?` |
| `RecipeScalerNative/App/AppContainer.swift` | Изменён: установка handler в `init` |

### Downstream consumers

- [x] **Все REST callers** — автоматически получают 401-обработку.
- [x] **Extensions** — Share/Action extensions используют `APIClient.shared`.
  Handler по умолчанию `nil` (extensions не делают wipe — только main app).
- [x] **Tests** — R6.

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| Любой authenticated REST → 401 | unauthorizedHandler вызван | `AuthSessionInvalidationTests` |

### Note

- Handler вызывается **до** throw ошибки наверх. Caller всё ещё видит 401 и
  может показать свою ошибку, но wipe уже запущен в фоне.
- `@Sendable` обязательно — `APIClient` nonisolated, handler может быть
  вызван с любого потока. Сам handler только запускает
  `Task { @MainActor in authService.handleDeviceTokenInvalid() }`.
- Extensions не устанавливают handler (остаётся `nil`) — они не должны
  вайпать сессию, только main app.

---

## R5 — YjsSyncService auth_error handler

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` | Изменён: `authInvalidationHandler: ((AccountInvalidationReason) async -> Void)?`, обновлён handler `client.on("auth_error")` |
| `RecipeScalerNative/App/AppContainer.swift` | Изменён: установка handler в `init` |

### Downstream consumers

- [x] **Socket protocol** — сервер уже шлёт `auth_error` с `message`.
- [x] **Tests** — R6 (через mock handler).

### Positive invariants

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| Socket `auth_error` "Account deleted" | `authInvalidationHandler` вызван с `.socketSignal` | `AuthSessionInvalidationTests.test_socket_account_deleted_wipes` |
| Socket `auth_error` с другим message | handler **не** вызван, `connectionState == .error(...)` | существующий тест + manual |

### Note

- Handler — optional closure, по умолчанию `nil` (для preview/tests).
- В `AppContainer.init` после создания `auth` и `sync`:
  `sync.authInvalidationHandler = { [weak auth] reason in await auth?.handleAccountDeleted(reason: reason) }`.

---

## R6 — Unit-тесты AuthSessionInvalidationTests

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNativeTests/AuthSessionInvalidationTests.swift` | Создан |

### Покрытие

5 positive invariants из spec.md (все из таблицы).

### Note

- Использовать паттерн `checkUserExistsProvider`-style injection для
  mock exchange (новый `exchangeSeedForTokenProvider`).
- `AppContainer.shared` — mock или `nil` (проверять teardown через
  spy-объект, не реальный контейнер).

---

## R7 — E2E AccountDeletionRuntimeSpec

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerNativeUITests/Specs/AccountDeletionRuntimeSpec.swift` | Создан |
| `RecipeScalerNativeUITests/Pages/AccountPage.swift` | Возможно изменён (helpers) |

### Покрытие

- Залогинен → backend удаляет аккаунт через REST fixture → socket `auth_error`
  → UI на AuthView, локальные данные пусты.

### Note

- Fixture: через `E2E_OVERRIDE_*` + серверный hook (DELETE FROM users).
- Требует `-DisableDebugAutoLogin=1` для симулятора DEBUG.

---

## Verify

- `xcodebuild build` — `RecipeScalerNative` scheme, all targets green.
- `xcodebuild test` — `AuthSessionInvalidationTests` (5 тестов), green.
- `xcodebuild test` — `AuthServiceStaleSessionTests` (regression check).
- `bash scripts/verify-ui-smoke.sh` — если UI-флоу менялся.
- E2E: `AccountDeletionRuntimeSpec` — green (если настроен fixture).
