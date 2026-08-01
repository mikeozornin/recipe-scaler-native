# Tasks: Удаление аккаунта (native) + Phase R

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Phase 1 (завершено в master): UI + AuthService.deleteAccount

- [x] T1.1 `AuthService.deleteAccount(seedPhrase:)` — POST `/api/auth/delete-account`, при успехе `wipeLocalSession()`
- [x] T1.2 `AccountSettingsViewModel.deleteAccount(seedPhrase:syncService:)` — вызов AuthService → teardown
- [x] T1.3 `AccountView.dangerZoneSection` + warning alert + seed sheet
- [x] T1.4 Accessibility-идентификаторы (`delete_account_*`)
- [x] T1.5 i18n-строки `account.delete.*` + `account.danger-zone`
- [x] T1.6 UITest полный flow + cancel на обоих шагах

## Phase R — Runtime recovery (parity с web US5/US6)

### R1 — AuthRevocationConstants

- [ ] T.R1.1 Создать `RecipeScalerCore/Networking/AuthRevocationConstants.swift`
- [ ] T.R1.2 Константа `accountDeletedSocketMessage = "Account deleted"` (parity с web)

### R2 — AuthService.handleAccountDeleted + re-entry guard

- [ ] T.R2.1 Добавить `enum AccountInvalidationReason { case socketSignal, restInvalidation }`
- [ ] T.R2.2 Добавить `enum SessionWipeReason { case explicitLogout, staleSession, accountDeletedSocket, accountDeletedRest, deviceTokenInvalidRecovery404, lightRevoke }`
- [ ] T.R2.3 Переделать `wipeLocalSession()` → `wipeLocalSession(reason: SessionWipeReason)`
- [ ] T.R2.4 Добавить `private var isHandlingAccountInvalidation = false` (re-entry guard)
- [ ] T.R2.5 Добавить `func handleAccountDeleted(reason: AccountInvalidationReason) async` — guard → wipe → `AppContainer.shared?.sync.clearSessionForLogout()` + `stopForLogout()`
- [ ] T.R2.6 Добавить `RecipeSnapshotStore.clear()` + Live Activity invalidate в wipe flow (если ещё нет)
- [ ] T.R2.7 `AppLog.info(.app, "account_invalidation", data: ["reason": ..., "source": ...])`

### R3 — AuthService.handleDeviceTokenInvalid (seed exchange recovery)

- [ ] T.R3.1 Добавить `var exchangeSeedForTokenProvider: (String) async throws -> ExchangeOutcome` для test injection
- [ ] T.R3.2 Добавить `enum ExchangeOutcome { case token(String), userNotFound, transient }`
- [ ] T.R3.3 Реализовать `func handleDeviceTokenInvalid() async` — вызов provider → ветвление
- [ ] T.R3.4 Detect "User not found": статус 404 OR message contains "not found" (case-insensitive)
- [ ] T.R3.5 При `.userNotFound` → `handleAccountDeleted(reason: .restInvalidation)`
- [ ] T.R3.6 При `.token` → `applySession(userId:deviceToken:)` (сессия восстановлена)
- [ ] T.R3.7 При `.transient` → `wipeLocalSession(reason: .lightRevoke)` без `stopForLogout`

### R4 — APIClient.shared centralized 401 interceptor

- [ ] T.R4.1 Добавить `var unauthorizedHandler: (@Sendable () async -> Void)?` на `APIClient`
- [ ] T.R4.2 В местах 401-обработки (`APIError.httpError(401)`) — вызывать handler если установлен
- [ ] T.R4.3 В `AppContainer.init` — установка handler: `Task { @MainActor in await auth.handleDeviceTokenInvalid() }`
- [ ] T.R4.4 Handler не дедлокит (test с concurrent requests)
- [ ] T.R4.5 Extensions НЕ устанавливают handler (по умолчанию `nil`)

### R5 — YjsSyncService auth_error handler

- [ ] T.R5.1 Добавить `var authInvalidationHandler: ((AccountInvalidationReason) async -> Void)?` на `YjsSyncService`
- [ ] T.R5.2 В `client.on("auth_error")` (строка ~1384): парсить `message`
- [ ] T.R5.3 Если `message == AuthRevocationConstants.accountDeletedSocketMessage` → `Task { await authInvalidationHandler?(.socketSignal) }`
- [ ] T.R5.4 Иначе — текущее поведение (`setConnectionState(.error(...))`)
- [ ] T.R5.5 В `AppContainer.init` — установка handler: `sync.authInvalidationHandler = { [weak auth] reason in await auth?.handleAccountDeleted(reason: reason) }`

### R6 — Unit-тесты AuthSessionInvalidationTests

- [ ] T.R6.1 Создать `RecipeScalerNativeTests/AuthSessionInvalidationTests.swift`
- [ ] T.R6.2 `test_socket_account_deleted_wipes` — handler `.socketSignal` → wipe
- [ ] T.R6.3 `test_rest_401_exchange_404_wipes` — provider → `.userNotFound` → wipe + stopForLogout
- [ ] T.R6.4 `test_rest_401_exchange_success_keeps_session` — provider → `.token` → сессия жива
- [ ] T.R6.5 `test_rest_401_exchange_network_light_revoke` — provider → `.transient` → wipe без stopForLogout
- [ ] T.R6.6 `test_double_signal_single_wipe` — re-entry guard

### R7 — E2E AccountDeletionRuntimeSpec

- [ ] T.R7.1 Создать `RecipeScalerNativeUITests/Specs/AccountDeletionRuntimeSpec.swift`
- [ ] T.R7.2 Fixture: залогинить → backend DELETE FROM users → socket auth_error
- [ ] T.R7.3 Assert: UI на AuthView, `delete_account_button` отсутствует, Keychain пуст (через debug hook)

## Verify

- [ ] V.1 `xcodebuild build` — all targets green
- [ ] V.2 `xcodebuild test` — `AuthSessionInvalidationTests` green (5 тестов)
- [ ] V.3 `xcodebuild test` — `AuthServiceStaleSessionTests` regression green
- [ ] V.4 `xcodebuild test` — `AccountSettingsSpec` regression green
- [ ] V.5 E2E `AccountDeletionRuntimeSpec` green (если fixture доступен)
