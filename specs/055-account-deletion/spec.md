# Спецификация: Удаление аккаунта (native)

**Дата**: 2026-08-01
**Статус**: 🟢 Реализовано
**Canonical spec**: `../recipe-scaler-web/specs/055-account-deletion/spec.md` —
shared-контракты (API, БД, cleanup) описаны там. Здесь — native-пара и
локальный cleanup.

## Контекст и мотивация

Необратимое удаление аккаунта из iOS-клиента. Подтверждение — двухшаговое
(как в web): warning-alert → ввод seed-фразы. После успешного ответа сервера
локальные credentials и Yjs/контейнеры зачищаются (web parity: wipe **только
после** 2xx).

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

## Риски

- **R1.** `TextEditor.typeText` в UITest может не сработать на sheet при
  системном вводе. **Mitigation**: fallback на `seedInput.typeText` после
  `tap()`; тест помечен как soft-skip только если seed не зарегистрирован.
- **R2.** Warning-alert (system) кнопки не имеют accessibility id — ищем по
  EN label (`"Cancel"` / `"Continue"`); UITest runner не содержит
  `Localizable.xcstrings`.

## Ссылки

- Canonical: `../recipe-scaler-web/specs/055-account-deletion/spec.md`
- Native spec 041 — auth device tokens
- Native spec 054 — stale-session recovery (`wipeLocalSession`)
