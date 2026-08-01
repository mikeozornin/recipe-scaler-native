# Спецификация: Удаление аккаунта (native)

**Дата**: 2026-08-01
**Статус**: 🟡 Дорабатывается (Phase R — runtime recovery)
**Canonical spec**: `../recipe-scaler-web/specs/055-account-deletion/spec.md` —
shared-контракты (API, БД, cleanup) описаны там. Здесь — native-пара и
локальный cleanup, включая runtime-реакцию на server-side удаление
(online peer `auth_error` + offline REST 401 → exchange → 404).

## Контекст и мотивация

Необратимое удаление аккаунта из iOS-клиента. Подтверждение — двухшаговое
(как в web): warning-alert → ввод seed-фразы. После успешного ответа сервера
локальные credentials и Yjs/контейнеры зачищаются (web parity: wipe **только
после** 2xx).

**Phase R (runtime recovery):** баг — при удалении аккаунта из веба (или с
другого устройства) нативный клиент, оставшийся онлайн, держит устаревший
`SharedAuthStore.token` и `AuthService.isAuthenticated == true`. Сокет
получает `auth_error`, но обработчик только переводит `connectionState` в
`.error` и **не запускает wipe**. UI показывает «оффлайн», но данные не
чищены до холодного старта, где их подбирает spec 054
(`performStaleSessionHealthCheck`). Эта фаза добавляет паритет с веб-клиентом
`auth-session-revoked.ts`: ловим server-side invalidation в рантайме и
молча уходим на `AuthView` (silent UX — без баннеров).

## Цель

1. `AuthService.deleteAccount(seedPhrase:)` — POST `/api/auth/delete-account`,
   после успеха — `wipeLocalSession()` (best-effort, non-throwing).
2. `AccountSettingsViewModel.deleteAccount(seedPhrase:syncService:)` — сначала
   `AuthService.deleteAccount`, затем (только при успехе)
   `clearSessionForLogout` + `AppContainer.stopForLogout`.
3. UI: отдельная секция **Danger Zone** на экране Account (не внутри Data
   Management). Шаг 1 — system alert с Continue/Cancel; шаг 2 — sheet с
   TextEditor для seed-фразы, confirm disabled пока не 12 слов.

## Non-goals

- **Browser/другие платформы** — см. web spec.
- **Soft-delete / scheduled purge** — не в этом заходе.
- **Подтверждение через отдельный OTP/email** — подтверждение владения =
  seed-фраза.

## User stories

1. Пользователь открывает Profile → Danger Zone → Delete account → видит alert
   «Удалить аккаунт?» → Continue → вводит 12-словную секретную фразу →
   «Да, удалить аккаунт». Аккаунт удалён; в обычном запуске приложение
   возвращается на AuthView; локальные credentials (Keychain seed,
   SharedAuthStore, watch) и Yjs store зачищены. Под `E2E_OVERRIDE_USER_ID`
   shell остаётся, но Danger Zone исчезает (`authService.isAuthenticated ==
   false`). Тексты — parity с web `account.delete.*`.
2. Пользователь отменяет на warning (Cancel) или в seed-шаге (Cancel в навбаре
   sheet) → аккаунт не тронут, никаких запросов.
3. Пользователь вводит чужую/неверную seed-фразу → сервер возвращает 401 →
   ошибка показывается **в sheet** (`delete_account_error`), sheet остаётся
   открытым; локальные данные не тронуты (web US5).

## Требования

### Функциональные

- **F1.** `AuthService.deleteAccount(seedPhrase:)`:
  - Client-side проверка 12 слов (`split(whereSeparator: \.isWhitespace).count
    == 12`), иначе `AuthError.invalidSeedPhrase` — без сетевого запроса.
  - POST `/api/auth/delete-account` через `performAuthRequest` (Bearer token).
  - При `response.success == false` — `AuthError.apiError(statusCode: 400,
    message: response.error ?? "account.delete.failed")`.
  - При успехе — `wipeLocalSession()` (best-effort: Keychain seed,
    `SharedAuthStore.clear()`, watch purge, `isAuthenticated = false`). Не
    `try logout()`: сервер уже удалил аккаунт, Keychain-сбой не должен
    маскировать успех.
- **F2.** `AccountSettingsViewModel.deleteAccount(seedPhrase:syncService:)`:
  порядок строго: `AuthService.shared.deleteAccount` → (только при успехе)
  `syncService.clearSessionForLogout()` → `AppContainer.shared?.stopForLogout()`.
  Возвращает `nil` при успехе; при ошибке — `setStatus(from:)` + локализованная
  строка (локальные store/sync **не** трогаются).
- **F3.** UI: секция `dangerZoneSection` в `AccountView`:
  - Видна только при `authService.isAuthenticated`.
  - Кнопка `deleteAccountButton` (destructive role) → `.alert` warning с
    `account.delete.warning.continue` (destructive) / `.cancel`.
  - Continue → `.sheet` `AccountDeleteSeedSheet`.
  - `AccountDeleteSeedSheet`: TextEditor, `isPhraseValid` = 12 слов; confirm
    disabled пока невалидно или `isDeleting`; `interactiveDismissDisabled` во
    время запроса; sheet закрывается **только при успехе**; при ошибке —
    footer `delete_account_error`.
- **F4.** Accessibility-идентификаторы: `delete_account_button`,
  `delete_account_seed_input`, `delete_account_confirm_button`,
  `delete_account_cancel_button`, `delete_account_error` (app
  `AccessibilityIdentifiers.swift` + UITest `UIA`).

### Нефункциональные

- **N1.** i18n: все строки через `Localizable.xcstrings`
  (`account.delete.*`, `account.danger-zone`, `account.delete.failed`).
- **N2.** Логи — только англ. (`AppLog`), без seed/PII.
- **N3.** UITest: полный flow + отмена на обоих шагах.

## Downstream consumers (изменяемое состояние)

- `AuthService.userId`, `.token`, `.isAuthenticated` — читают `ContentView`,
  `AccountSettingsViewModel`, watch через `SharedAuthStore`.
- `SharedAuthStore` — читают extensions, watch, `APIClient.shared`.
- `YjsSyncService` / `AppContainer` — останавливаются **после** успешного
  server-call.

## Positive invariants (для тестов)

| Эффект | Инвариант | Где проверять |
|--------|-----------|---------------|
| Успешный DELETE | seed sheet закрыт; Profile tab жив (E2E shell); `delete_account_button` отсутствует | `AccountSettingsSpec.test_055_fullDeleteFlow` |
| Cancel на warning | `accountPage.root` существует, seed sheet не показан | `AccountSettingsSpec.test_055_cancelOnWarningKeepsAccount` |
| Cancel на seed | seed sheet закрыт, аккаунт цел | `AccountSettingsSpec.test_055_cancelOnSeedStepKeepsAccount` |
| Confirm disabled | при < 12 слов кнопка disabled | unit / UI-проверка |

## Acceptance criteria

- [ ] AC1. `xcodebuild build` green для основного target.
- [ ] AC2. `xcodebuild test` green для `AccountSettingsSpec` (три новых теста).
- [ ] AC3. Локализации `account.delete.*` присутствуют в `Localizable.xcstrings`
  (ru + en).
- [ ] AC4. Web-пара: `recipe-scaler-web/specs/055-account-deletion/spec.md` —
  canonical shared-контракты.

## Runtime recovery (native parity с web US5/US6)

Phase R. Поведение при удалении аккаунта **на другом устройстве** или **на
сервере напрямую**, пока нативный клиент работает. Контракт —
`../recipe-scaler-web/specs/shared/auth.md` (US5 online peers + US6 offline
wipe) и `recipe-scaler-web/recipe-scaler/src/services/auth-session-revoked.ts`.

### Триггеры wipe в рантайме

1. **Socket.IO `auth_error`** с `message == "Account deleted"` (константа
   `AUTH_ACCOUNT_DELETED_SOCKET_MESSAGE`). Сервер шлёт это post-commit через
   `realtime.disconnectUser` после `DELETE FROM users`.
2. **REST 401** с `code == "device_token_invalid"` (Bearer отклонён, потому
   что строка `devices` уже снесена CASCADE). Клиент пытается
   `exchange-seed-for-token`:
   - `200` (токен восстановлен) → сессия жива, **wipe не нужен**.
   - `404 "User not found"` → аккаунт удалён пока устройство было оффлайн →
     полный `wipeLocalSession`.
   - 5xx / network failure → light-revoke (`wipeLocalSession` без
     `stopForLogout`), пользователь может retry.

### Требования

- **FR-R1.** `AuthService.handleAccountDeleted(reason:) async` —
  централизованный entry point. Re-entry guard (`isHandlingAccountInvalidation`)
  чтобы параллельные socket `auth_error` + REST 401 не дублировали teardown.
  Делегирует в `wipeLocalSession(reason:)`, затем в
  `AppContainer.shared?.sync.clearSessionForLogout()` + `stopForLogout()`.
  Silent UX: `isAuthenticated = false` → `ContentView.onChange` уводит на
  `AuthView` без баннеров/alerts.
- **FR-R2.** `AuthService.handleDeviceTokenInvalid() async` — вызывается из
  APIClient 401-interceptor. Пробует `exchangeSeedForToken(seed:)` (seed из
  app-local Keychain). Различает:
  - `AuthError.apiError(404, "User not found" | message contains "not found")`
    → `handleAccountDeleted(reason: .restInvalidation)`.
  - Успех → `applySession(...)` (сессия восстановлена, остаёмся).
  - Любая другая ошибка → `wipeLocalSession(reason: .lightRevoke)`,
    `isAuthenticated = false`, но **без** `stopForLogout` (пользователь
    может пере-логиниться, данные не потеряны).
- **FR-R3.** `APIClient.shared` — централизованный 401-interceptor:
  `unauthorizedHandler: (@Sendable () async -> Void)?`. При возврате
  `APIError.httpError(401)` (или `APIError.unauthorized`) из любого
  authenticated REST-запроса — вызывается handler. Handler делегирует в
  `AuthService.handleDeviceTokenInvalid()` через `Task { @MainActor in ... }`.
  Вся wipe-логика — на MainActor (AuthService `@MainActor`); interceptor
  только запускает task и сразу бросает ошибку наверх (caller видит 401).
  Thread-safety: `APIClient` остаётся `nonisolated sendable`, handler только
  `@Sendable` closure.
- **FR-R4.** `YjsSyncService` auth_error handler (сейчас на строке ~1384):
  парсит `message` из payload. Если
  `== AuthRevocationConstants.accountDeletedSocketMessage` →
  `Task { await authInvalidationHandler?(.socketSignal) }`. Иначе — текущее
  поведение (`setConnectionState(.error(...))`).
- **FR-R5.** Idempotency: повторные `auth_error` / 401 пока wipe в полёте
  игнорируются (re-entry guard в `handleAccountDeleted`). Один сигнал —
  один wipe.
- **FR-R6.** `DebugSimulatorAutoLogin` совместимость: после wipe в DEBUG
  simulator, следующая попытка bootstrap повторно инжектит debug-сессию
  (через `applyDebugSimulatorAutoLoginCredentials(preferBundledToken: false)`
  — уже есть в `AppContainer.bootstrap`). Не блокирует флоу восстановления.

### Downstream consumers (изменяемое состояние)

- `AuthService.isAuthenticated`, `.userId`, `.token` — читают `ContentView`
  (через `onChange` → `clearSessionForLogout` + `stopForLogout`),
  `AccountSettingsViewModel`, watch через `SharedAuthStore`.
- `SharedAuthStore` — читают extensions, watch, `APIClient.shared`. Wipe
  очищает через `SharedAuthStore.clear()`.
- `YjsSyncService.authInvalidationHandler` — новая closure-инъекция.
  Устанавливается из `AppContainer.init` после создания `auth` и `sync`.
- `APIClient.shared.unauthorizedHandler` — новая closure-инъекция.
  Устанавливается из `AppContainer.init`.
- `RecipeSnapshotStore` (Home Screen Quick Actions / Live Activity) —
  должен быть очищен в `wipeLocalSession` (добавить в Phase R, если ещё нет).
- Live Activity (Timer) — invalidate при wipe, иначе остаётся с устаревшим
  recipe name.
- `WatchCredentialsBridge` — уже чистится в текущем `wipeLocalSession`.

### Positive invariants (для тестов)

| Эффект | Инвариант | Где проверять |
|--------|-----------|---------------|
| Socket `auth_error` "Account deleted" | `isAuthenticated == false`, Keychain seed пуст, `SharedAuthStore` пуст, `clearSessionForLogout` вызван, `stopForLogout` вызван | `AuthSessionInvalidationTests.test_socket_account_deleted_wipes` |
| REST 401 `device_token_invalid` + exchange 404 | `isAuthenticated == false`, `wipeLocalSession` вызван, `stopForLogout` вызван | `AuthSessionInvalidationTests.test_rest_401_exchange_404_wipes` |
| REST 401 `device_token_invalid` + exchange success | `isAuthenticated == true`, новый токен применён, wipe **не** вызван | `AuthSessionInvalidationTests.test_rest_401_exchange_success_keeps_session` |
| REST 401 + exchange network failure | `isAuthenticated == false`, `wipeLocalSession` вызван, `stopForLogout` **не** вызван (light revoke) | `AuthSessionInvalidationTests.test_rest_401_exchange_network_light_revoke` |
| Double `auth_error` подряд | wipe вызван ровно 1 раз | `AuthSessionInvalidationTests.test_double_signal_single_wipe` |

### Note

- Центральный interceptor в `APIClient` выбран вместо точечной обработки в
  call sites для паритета с вебовским `fetchWithAuth`. Любой новый
  authenticated REST-запрос автоматически получает 401-обработку.
- Seed exchange recovery добавляет сетевой запрос (до 3с таймаут) перед
  wipe. Это намеренно: device_token может быть отозван по другим причинам
  (rotate, admin revoke), не только при удалении аккаунта. Wipe только
  когда сервер подтвердил `User not found`.
- `YjsSyncService` построен в `AppContainer.init` до `AuthService`, но оба
  — свойства `let` на контейнере. Замыкание `authInvalidationHandler`
  устанавливается в `init` после создания обоих сервисов.

## Риски

- **R1.** `TextEditor.typeText` в UITest может не сработать на sheet при
  системном вводе. **Mitigation**: fallback на `seedInput.typeText` после
  `tap()`; тест помечен как soft-skip только если seed не зарегистрирован.
- **R2.** Warning-alert (system) кнопки не имеют accessibility id — ищем по
  EN label (`"Cancel"` / `"Continue"`); UITest runner не содержит
  `Localizable.xcstrings`.
- **R3 (Phase R).** `APIClient` — `nonisolated sendable`, общий для app и
  extensions. unauthorizedHandler не должен дедлокить на MainActor.
  **Mitigation:** interceptor только запускает `Task { @MainActor in ... }`
  и сразу бросает ошибку; вся синхронная работа на MainActor.
- **R4 (Phase R).** Seed exchange recovery добавляет сетевой запрос (до 3с)
  перед wipe — задержка видна пользователю как «оффлайн-баннер».
  **Mitigation:** light-revoke путь не блокирует UI; при socket `auth_error`
  recovery не делаем (сервер уже сказал "Account deleted" — доп. проверка
  не нужна).
- **R5 (Phase R).** `DebugSimulatorAutoLogin` после wipe повторно
  инжектит debug-сессию в `bootstrap` — тестирование runtime recovery на
  симуляторе требует `-DisableDebugAutoLogin=1`.
- **R6 (Phase R).** Live Activity / Widget / Watch могут держать устаревший
  userId. **Mitigation:** `wipeLocalSession` чистит
  `WatchCredentialsBridge`, `RecipeSnapshotStore`, Live Activity
  invalidate (добавляется в Phase R).

## Ссылки

- Canonical: `../recipe-scaler-web/specs/055-account-deletion/spec.md`
- Web parity: `../recipe-scaler-web/recipe-scaler/src/services/auth-session-revoked.ts`,
  `../recipe-scaler-web/recipe-scaler/src/services/wipe-local-session.ts`
- Native spec 041 — auth device tokens
- Native spec 054 — stale-session recovery (`wipeLocalSession`, cold-start path)
