# Задачи: Device tokens — замена plaintext `x-user-id` на bearer-токен

Чеклист выполнения. Зачеркиваем пункт по факту, не заранее.

## Spec Kit

- [x] `spec.md` — постановка, user stories, acceptance criteria
- [x] `plan.md` — фазы, декомпозиция для PR'ов
- [x] `tasks.md` — детальный чеклист
- [x] `contracts/login-response.md` — формат response `/api/auth/login-with-seed`, `/register-auto`, `/exchange-seed-for-token`
- [x] `contracts/socketio-handshake.md` — формат Socket.IO handshake auth (transitional: `io.use()` + legacy `emit('auth')` до cutoff)
- [x] `contracts/watchconnectivity-creds-update.md` — stub; контракт обновлён in-place в `specs/039-watchos-timers/contracts/watchconnectivity-creds.md`
- [x] Ревью `spec.md` пользователем → добор контекста при необходимости

## Фаза 1 — Backend (`recipe-scaler-web`)

### DB

- [ ] Migration: `ALTER TABLE devices ADD COLUMN device_token_hash TEXT UNIQUE` (Postgres multi-NULL semantics — см. spec F19)
- [ ] Migration: `ALTER TABLE devices ADD COLUMN device_token_expires_at TIMESTAMPTZ DEFAULT NULL`
- [ ] Migration: индекс на `device_token_hash` для быстрого lookup
- [ ] Migration: `ALTER TABLE users ADD COLUMN legacy_auth_cutoff_at TIMESTAMPTZ DEFAULT NULL`
- [ ] Migration: индекс на `users.legacy_auth_cutoff_at` (для middleware lookup)
- [ ] Migration: `CREATE TABLE auth_audit_log` (см. spec F21)
- [ ] Backfill: для существующих записей `device_token_hash = NULL`, `legacy_auth_cutoff_at = NULL` (без токена, работают на `x-user-id` фолбэке)
- [ ] **Существующий** `UNIQUE(user_id, device_id)` на `devices` остаётся как есть (`create-dev-tables.sql:92`) — не дублировать

### Service layer

- [ ] `server/src/utils/token-hash.ts` (новый общий util): `hashToken(token)` — SHA-256 hex. Extract из `mcp-auth-service.ts:50-52`. Используется и `mcp-auth-service`, и `device-token-service`.
- [ ] `server/src/services/device-token-service.ts` (новый): `generateToken()` — 32 random bytes → base64url (см. `mcp-auth-service.ts:43-45`)
- [ ] `lookupByHash(hash)` → `{user_id, device_id} | null` (DB-side `WHERE device_token_hash = $1`, без app-level compare)
- [ ] `invalidateByDevice(user_id, device_id)` → `UPDATE devices SET device_token_hash = NULL`
- [ ] `issueForDevice(user_id, device_id)` → generate, hash, upsert (с conflict-target `(user_id, device_id)`), return plaintext once
- [ ] `ensureLegacyCutoffSet(user_id)` → idempotent: если `users.legacy_auth_cutoff_at IS NULL`, установить `NOW() + LEGACY_AUTH_GRACE_DAYS` (default 7). Вызывается при любой успешной миграции/exchange/login с новым токеном.
- [ ] `allDevicesMigratedForUser(user_id)` → bool: все ли активные (`last_seen > NOW() - INTERVAL '90 days'`, см. spec F20) device'ы user'a имеют `device_token_hash IS NOT NULL`. Используется web-баннером.
- [ ] `touchLastSeen(user_id, device_id)` → throttled UPDATE `last_seen = NOW()` (не чаще раза в час, сравнение с текущим `last_seen`)
- [ ] `cleanupOrphanDevices()` — cron daily: `DELETE FROM devices WHERE device_token_hash IS NULL AND last_seen < NOW() - INTERVAL '90 days'`. **Required**, не optional (см. spec F19, AC21).
- [ ] `cleanupAuditLog()` — cron daily: `DELETE FROM auth_audit_log WHERE ts < NOW() - INTERVAL '90 days'`.

### Auth routes

- [ ] `POST /api/auth/login-with-seed` (`server/src/routes/auth.ts:424`): response `{success, data: {user: {id, data_version}, device_token}}` + legacy `user.id` (transitional shim). Generation + upsert в `devices`. Вызов `ensureLegacyCutoffSet`. Точный shape — `contracts/login-response.md`.
- [ ] `POST /api/auth/register-auto` (`auth.ts:485`): response `{success, data: {user: {id, data_version}, seed_phrase, device_token}}`. Удалить `seed_hash` из response (internal leak). Вызов `ensureLegacyCutoffSet`.
- [ ] `POST /api/auth/exchange-seed-for-token` (новый route): body `{seed_phrase, device_id, platform, app_version}` → валидация seed → lookup user → upsert device → response `{success, data: {user: {id, data_version}, device_token}}`. После успеха — `ensureLegacyCutoffSet(user_id)`. Покрыть **существующим** `authRateLimiter` (5 req / 15 min per IP — `middleware/rateLimiter.ts:104-126`).
- [ ] `POST /api/auth/logout` (`auth.ts:546`): добавить `UPDATE devices SET device_token_hash = NULL WHERE user_id AND device_id` (перед существующим delete device row, либо вместо — row остаётся для history, см. spec F6, F19).
- [ ] `GET /api/auth/legacy-status` — для web-баннера: `{success, data: {legacy_auth_cutoff_at, all_migrated}}`. Использует `allDevicesMigratedForUser`.
- [ ] Все endpoints, которые issue'ят device_token, должны вызывать `ensureLegacyCutoffSet(user_id)` и писать в `auth_audit_log` (`token_issued`, `cutoff_set`).

### Middleware

- [ ] `server/src/middleware/auth.ts:resolveAuth()` (line 84-115): добавить приоритет 1 — device_token Bearer → `device_token_hash` lookup (DB-side). При совпадении:
  - `req.user_id = device.user_id`
  - `req.device_id = device.device_id`
  - `req.auth_type = 'device_token'`
  - Throttled `touchLastSeen` (через `device-token-service`)
- [ ] Сохранить приоритет 2 (OAuth Bearer из `mcp-auth-service`) — legacy `x-user-id` становится приоритетом 3.
- [ ] Legacy `x-user-id` middleware: после lookup user'a проверить `legacy_auth_cutoff_at`. Если cutoff в прошлом → 401 «legacy auth disabled, please update» + audit log `legacy_rejected`. Если NULL или в будущем → accept (grace).

### Socket.IO (transitional — см. `contracts/socketio-handshake.md`)

- [ ] `server/src/index.ts:138` — добавить `io.use()` handshake middleware: валидация `socket.handshake.auth.token` через `DeviceTokenService.lookupByHash()`. На handshake проставлять `socket.data.userId`, `socket.data.deviceId`, `socket.data.authType = 'device_token'`. При невалидном токене → `next(new Error('unauthorized'))`.
- [ ] `socket.on('auth', {userId, deviceId})` (`index.ts:139`) — **оставить на transitional period**, но добавить cutoff-проверку: если `users.legacy_auth_cutoff_at` в прошлом → `socket.emit('auth_error', {message: 'Legacy auth disabled, please update'})` + `socket.disconnect(true)` + audit log `legacy_rejected`.
- [ ] Auth timeout: если нет ни handshake-token, ни `emit('auth')` в течение 10 сек → `socket.disconnect(true)`.
- [ ] **Не использовать** `?token=` query fallback (гарантированный leak в nginx access logs).
- [ ] **Post-cleanup** (отдельный PR после истечения последнего активного cutoff): удалить `socket.on('auth')` handler, auth-timeout. Сделать `io.use()` обязательным.

### Tests

- [ ] `server/src/services/__tests__/device-token-service.test.ts` — новый
- [ ] `server/src/routes/__tests__/auth.test.ts` — расширить: проверка `device_token` в response login/register-auto/exchange
- [ ] `server/src/routes/__tests__/auth.test.ts` — logout инвалидирует токен
- [ ] `server/src/middleware/__tests__/auth.test.ts` — Bearer lookup, throttled `last_seen`, fallback на `x-user-id` во время grace, отказ `x-user-id` после cutoff
- [ ] `server/src/services/__tests__/legacy-cutoff.test.ts` — `ensureLegacyCutoffSet` idempotent, `allDevicesMigratedForUser` игнорирует orphan rows
- [ ] Socket.IO integration test (см. test cases в `contracts/socketio-handshake.md`): handshake с токеном работает, без токеня + emit auth на cutoff-истёкшем → disconnect
- [ ] Audit log test: `token_issued`/`token_revoked`/`cutoff_set`/`cutoff_triggered`/`legacy_rejected` пишутся, токен/seed НЕ пишутся
- [ ] Smoke test в staging: `curl POST /api/auth/login-with-seed` → валидный ответ

## Фаза 2 — Web/PWA (`recipe-scaler-web/recipe-scaler`)

### Sub-phase 2.0 — Centralize auth-token accessor (B5, обязательно до остальных пунктов)

**Inventory**: сегодня `localStorage.getItem('userId')` для auth-заголовков разбросан по 30+ файлам (`App.tsx`, `seed-auth.tsx`, `recipe-list.tsx`, `yjs-client.ts`, `timer-service.ts`, `push-service.ts`, `discovery-api.ts`, `recipe-image-api.ts`, `assistant-api.ts`, `avatar-api.ts`, `websocket-service.ts`, `simple-data-version-manager.ts`, `recipe-extractor.ts`, импортеры v1.1-v1.4, и др.).

- [ ] Создать `src/services/auth-token.ts` с единым accessor:
  ```typescript
  export function getAuthToken(): { type: 'bearer'; token: string } | { type: 'legacy'; userId: string } | null {
    const token = localStorage.getItem('device_token');
    if (token) return { type: 'bearer', token };
    const userId = localStorage.getItem('userId');
    if (userId) return { type: 'legacy', userId };
    return null;
  }

  export function applyAuthHeaders(headers: HeadersInit = {}): HeadersInit {
    const auth = getAuthToken();
    if (auth?.type === 'bearer') {
      return { ...headers, 'Authorization': `Bearer ${auth.token}` };
    }
    if (auth?.type === 'legacy') {
      return { ...headers, 'x-user-id': auth.userId };
    }
    return headers;
  }
  ```
- [ ] Codemod: заменить **все** чтения `localStorage.getItem('userId')` для построения auth-заголовков на `applyAuthHeaders()` или `getAuthToken()`. Проверка: `rg "localStorage.getItem\(['\"]userId" --type ts --type tsx` должен вернуть только non-auth usage (analytics, debugging, и т.п.).
- [ ] Обновить `src/services/auth-headers.ts:headersForUser/multipartHeadersForUser` — делегируют в `applyAuthHeaders()`.
- [ ] **AC13.1**: `rg "localStorage\.getItem\(['\"]userId['\"]\)"` возвращает только non-auth usage после codemod.

### Sub-phase 2.1 — Migration + storage

- [ ] `src/services/v2-auth-api.ts` — типы response расширить `device_token: string` (точный shape — `contracts/login-response.md`)
- [ ] `src/services/v2-auth-api.ts` — новый метод `exchangeSeedForToken({seed_phrase, device_id})`
- [ ] `src/App.tsx:147-186` startup миграционный шаг: если `localStorage.seed_phrase` есть и `localStorage.device_token` нет → `exchangeSeedForToken` тихо → записать в localStorage
- [ ] После успешной миграции — `localStorage.removeItem('seed_phrase')` (см. spec F18, R2: seed больше не нужен в localStorage после exchange)
- [ ] `src/pages/seed-auth.tsx:401` login — `localStorage.setItem('device_token', response.device_token)`
- [ ] `src/pages/seed-auth.tsx:738` logout — `localStorage.removeItem('device_token')`

### Sub-phase 2.2 — Socket.IO

- [ ] `src/services/yjs-client.ts:449` — `io(wsUrl, {transports, auth: token ? { token } : undefined})`. Без `?token=` query.
- [ ] `src/services/yjs-client.ts:489,2287` — `socket.emit('auth', {userId, deviceId})` отправляется **только если нет token** (legacy fallback, grace period). Если есть token — emit не нужен, `io.use()` уже валидировал.
- [ ] Точный контракт — `contracts/socketio-handshake.md`.

### Sub-phase 2.3 — Banner

- [ ] **Баннер grace period** в списке рецептов: новый компонент `src/components/legacy-auth-banner.tsx`
  - Запрашивает `GET /api/auth/legacy-status` → `{legacy_auth_cutoff_at, all_migrated}` (новый endpoint)
  - Если `legacy_auth_cutoff_at` в будущем и `all_migrated = false` — показывает баннер
  - Текст: «Более защищённая схема авторизации. Откройте приложение на всех устройствах в течение N дней (до {date}).» + кнопка «Подробнее»
  - Скрывается при `all_migrated = true` или после cutoff
  - i18n: ключи в `recipe-scaler/src/locales/*.json`

### Sub-phase 2.4 — Tests

- [ ] E2E: новый пользователь → register → `device_token` в localStorage → все запросы с Bearer
- [ ] E2E: миграция (имитация старого состояния) → exchange тихо → работает
- [ ] E2E: баннер показывается после первого login (legacy cutoff установлен), скрывается после миграции всех устройств
- [ ] E2E: Socket.IO подключение с `auth.token` работает; без token + cutoff истёк → disconnect

## Фаза 3 — iOS native (`recipe-scaler-native`)

### SharedAuthStore

- [ ] `RecipeScalerCore/Auth/SharedAuthStore.swift` — `tokenAccount = "token"`, `static var token: String?` getter/setter (через тот же raw SecItem path, тот же access group)
- [ ] `SharedAuthStore.clear()` — очищает и `userId`, и `token`
- [ ] `SharedAuthStoreTests` — token roundtrip (write/read/clear), access group работает в симуляторе (best-effort — на девайсе с реальным entitlement)

### APIClient

- [ ] `RecipeScalerCore/Networking/APIClient.swift` — без структурных изменений; `configure(authToken:)` уже есть. Документировать что caller ответственный за persisting токена.
- [ ] Verify: bearer branch в `buildRequest` (line 122-127) срабатывает когда `authToken != nil`.

### AuthService

- [ ] `RecipeScalerNative/Services/AuthService.swift` — `AuthResponse`, `RegisterAutoResponse` декодят `device_token`
- [ ] `loginWithSeed` (line 288-336) — после успеха: `SharedAuthStore.token = data.device_token`, `apiClient.configure(authToken: data.device_token)`
- [ ] `registerAuto` (line 247-283) — то же
- [ ] `logout` (line 339-358) — `SharedAuthStore.token = nil`, `apiClient.configure(authToken: nil)`
- [ ] `restoreAuthenticationState` (line 136-149) — если `SharedAuthStore.token != nil` → `apiClient.configure(authToken: ...)`. Иначе если есть `userId` и есть seed в app-local Keychain → `exchangeSeedForToken` миграционный шаг.

### Migration flow

- [ ] `AuthService.exchangeSeedForToken(seed, deviceId)` — новый метод, вызывает `/api/auth/exchange-for-token`, persistит `SharedAuthStore.token`
- [ ] В `restoreAuthenticationState` — если token == nil и seed есть → запустить exchangeSeedForToken асинхронно. На ошибку — игнор (продолжаем на `x-user-id` fallback, не ломаем пользователя).
- [ ] Migration — fire-and-forget; UI блокируется только если backend недоступен (тогда работаем на legacy `x-user-id`).

### AppContainer

- [ ] `RecipeScalerNative/App/AppContainer.swift:153-157` — sync `APIClient.shared.configure(authToken: SharedAuthStore.token)` на construction
- [ ] `AppContainer.bootstrap(userId:)` — после `configure(userId:)` вызвать `configure(authToken: SharedAuthStore.token)` если есть

### YjsSyncService

- [ ] `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1255` — Socket.IO handshake с `auth: ["token": token]` если token есть. Legacy `emit("auth", ["userId": ...])` — только если token пустой (grace fallback). Точный контракт — `specs/041-auth-device-tokens/contracts/socketio-handshake.md`.
- [ ] `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1468-1470` — `socket.emit("auth", {userId})` удалить **только в post-cleanup PR** (после истечения последнего активного cutoff).
- [ ] Socket.IO lib поддерживает `auth: { token }` handshake — verify (Socket.IO v4+).

### Tests

- [ ] `SharedAuthStoreTests` — token roundtrip
- [ ] `AuthServiceTests` (если есть) — `loginWithSeed` persistит token, `logout` очищает
- [ ] Migration test — восстановление state без token, с seed → exchangeSeedForToken вызывается

## Фаза 4 — iOS extensions

- [ ] `ShareExtensionUI/ShareView.swift:131-137` — `submit()`: `guard let token = SharedAuthStore.token else { phase = .notSignedIn; return }`, `APIClient.shared.configure(authToken: token)`
- [ ] `ShareExtensionUI/ShareView.swift:109` — discovery gate на `SharedAuthStore.token != nil` вместо `userId`
- [ ] `ActionExtension/ActionViewController.swift` — без изменений (наследует ShareView)
- [ ] Manual QA: Share Extension из Safari → recipe импортируется под правильным аккаунтом; logout → Share Extension показывает notSignedIn

## Фаза 5 — Apple Watch

- [ ] `RecipeScalerNative/Services/WatchCredentialsBridge.swift` — `publish(userId:token:)` в дополнение к `publish(userId:)`. Payload `transferUserInfo(["userId": ..., "token": ..., "version": 2])`. На logout — `["userId": NSNull(), "token": NSNull(), "version": 2]`. Точный контракт — `specs/039-watchos-timers/contracts/watchconnectivity-creds.md` (обновлён in-place).
- [ ] `RecipeScalerNative/Services/AuthService.swift` — wire-up в `loginWithSeed`, `registerAuto`, `logout`: `WatchCredentialsBridge.shared.publish(userId:token:)`.
- [ ] `RecipeScalerNativeWatch/Services/WatchCredentialsStore.swift` — `token` property, watch-local Keychain (account "token", service "com.recipescaler.watch", `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = kCFBooleanFalse` — см. spec 041 F22).
- [ ] `RecipeScalerNativeWatch/App/RecipeScalerNativeWatchApp.swift:18-24` — init configure: prefer `APIClient.shared.configure(authToken: WatchCredentialsStore.token)`, fallback на `configure(userId:)` если token пустой.
- [ ] `RecipeScalerNativeWatch/Services/WatchCredentialsBridge.swift` — handle payload version 1 (без `token`) и version 2 (с `token`). Forward-compat.
- [ ] **Контракт уже обновлён** в `specs/039-watchos-timers/contracts/watchconnectivity-creds.md` (in-place, не `-update.md`).
- [ ] Manual QA: paired simulator, login на iPhone → watch получает token → timers ходят под Bearer; logout → watch not-authorized

## Фаза 6 — Финал и приёмка

> **Полная структура приёмки** (тестовая пирамида, acceptance gate per phase, E2E сценарии, rollback-тесты, production rollout checklist, manual QA, security regression) — в `plan.md`, секция «Фаза 6 — Финал и приёмка».

- [ ] All unit tests green (`npm test`, `xcodebuild test`)
- [ ] All integration tests green (middleware, Socket.IO, DB migration up/down)
- [ ] All 8 E2E сценариев проходят в staging (см. `plan.md` § Acceptance gate)
- [ ] All 5 rollback-тестов пройдены
- [ ] Production rollout checklist подписан (см. `plan.md`)
- [ ] Manual QA checklist выполнен для extensions + watch
- [ ] Security regression tests добавлены в CI (rate-limit, audit-log, hash-unique, WS-spoof)
- [ ] Закрыть Linear [MIK-117](https://linear.app/mikeozornin/issue/MIK-117/review-33-rasshireniya-autentificiruyutsya-tolko-plaintext-ne) с комментарием-ссылкой на PR'ы
- [ ] Коммиты в оба репо, отдельные PR'ы по плану

## Фаза 7 — Post-cutoff cleanup (отдельный PR после истечения последнего активного `legacy_auth_cutoff_at`)

- [ ] Backend: удалить `socket.on('auth')` handler в `server/src/index.ts`
- [ ] Backend: удалить auth-timeout в `io.on('connection')`
- [ ] Backend: сделать `io.use()` обязательным (`if (!token) return next(new Error('unauthorized'))`)
- [ ] Backend: удалить `data.user.id` из response `/login-with-seed`, `/register-auto`, `/exchange-seed-for-token` (см. spec F17)
- [ ] Backend: удалить legacy `x-user-id` ветку из `resolveAuth` (`middleware/auth.ts:99-112`)
- [ ] Web: удалить `socket.emit('auth', {userId})` legacy-fallback в `yjs-client.ts`
- [ ] Native: удалить `socket.emit("auth", ...)` legacy-fallback в `YjsSyncService.swift`
- [ ] Verify: grep по `legacy_auth_cutoff_at` usage в middleware должен показать «dead code» → удалить
- [ ] Update `review-kilo-glm-5.2-recipe-scaler-native.md` — отметить finding #1 (Critical) и #33 как полностью remediated

## Документация

- [ ] `recipe-scaler-web/llm/API.md` — обновить auth секцию (device_token Bearer приоритет 1, OAuth Bearer приоритет 2, `x-user-id` приоритет 3 transitional)
- [ ] `recipe-scaler-native/AGENTS.md` — секция Auth обновить (Composition Root, SharedAuthStore.token)
- [ ] `recipe-scaler-web/AGENTS.md` — секция Auth обновить
- [ ] Контракт `specs/039-watchos-timers/contracts/watchconnectivity-creds.md` — **уже обновлён** in-place (spec 041 фаза 5)
- [ ] Update `review-kilo-glm-5.2-recipe-scaler-native.md` — отметить находки #1 и #33 как remediated со ссылкой на эту спеку
