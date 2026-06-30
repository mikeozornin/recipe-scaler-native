# План: Device tokens — замена plaintext `x-user-id` на bearer-токен

**Spec**: [spec.md](./spec.md)
**Линейные задачи**: [MIK-117](https://linear.app/mikeozornin/issue/MIK-117/review-33-rasshireniya-autentificiruyutsya-tolko-plaintext-ne) (нахождение #33), частично review finding #1.

## Cross-repo стратегия

Один spec, два репозитория. Все 3 PR готовятся и деплоятся одним батчем (без staggered rollout) — per-user grace period 7 дней покрывает race condition между деплоями.

1. **Backend** (`recipe-scaler-web`) — миграция БД, endpoint'ы, middleware (device_token + legacy cutoff logic), Socket.IO. Фолбэк на `x-user-id` сохраняется per-user в grace period (7 дней).
2. **Web/PWA** (`recipe-scaler-web/recipe-scaler/`) — centralized `getAuthToken()` accessor (sub-phase 2.0), миграция `localStorage`, прозрачный exchange на старте, `Authorization: Bearer` в заголовках, баннер grace period в списке рецептов.
3. **iOS native + extensions + watch** (`recipe-scaler-native`) — `SharedAuthStore.token`, `APIClient` refresh-на-401 **не нужен** (токен бессрочный), watch bridge. При 401 (после cutoff на устройстве, которое не успело мигрировать) — экран входа.

`x-user-id` остаётся per-user grace fallback 7 дней после первой миграции этого user'a. Cutoff управляет тремя устаревшими path одновременно: REST `x-user-id`, WS `socket.on('auth')`, response `data.user.id`. После истечения последнего активного cutoff — cleanup PR (фаза 7) удаляет все три.

## Фазы реализации

### Фаза 0 — Spec Kit (текущая)

- [x] `spec.md` — постановка, user stories, acceptance criteria
- [x] `plan.md` — этот файл
- [x] `tasks.md` — детальный чеклист
- [x] `contracts/login-response.md` — формат ответа `/api/auth/login-with-seed`, `/register-auto`, `/exchange-seed-for-token`
- [x] `contracts/socketio-handshake.md` — формат Socket.IO handshake auth (transitional: `io.use()` + legacy `emit('auth')` до cutoff)
- [x] `contracts/watchconnectivity-creds-update.md` — stub; контракт обновлён in-place в `specs/039-watchos-timers/contracts/watchconnectivity-creds.md`
- [x] Ревью `spec.md` пользователем → после одобрения реализация

### Фаза 1 — Backend (`recipe-scaler-web/server/`)

- [ ] DB migration: колонки `devices.device_token_hash` (UNIQUE, nullable), `devices.device_token_expires_at` (NULL default), `devices.last_seen` обновляем. Существующий `UNIQUE(user_id, device_id)` остаётся.
- [ ] DB migration: колонка `users.legacy_auth_cutoff_at` (TIMESTAMPTZ, nullable), индекс на ней.
- [ ] DB migration: таблица `auth_audit_log` (см. spec F21).
- [ ] Сервис `DeviceTokenService` (новый файл, рядом с `mcp-auth-service.ts`): `generateToken()`, `hashToken()` (extract в общий util `utils/token-hash.ts`), `lookupByHash()`, `invalidateByDevice()`, `ensureLegacyCutoffSet()`, `allDevicesMigratedForUser()`, `touchLastSeen()`, `cleanupOrphanDevices()`, `cleanupAuditLog()`.
- [ ] `POST /api/auth/login-with-seed` — возвращает `{success, data: {user: {id, data_version}, device_token}}` + legacy `user.id` shim. Generation + upsert в `devices`. Вызов `ensureLegacyCutoffSet`. Audit log.
- [ ] `POST /api/auth/register-auto` — возвращает `{success, data: {user: {id, data_version}, seed_phrase, device_token}}`. Удалить `seed_hash` из response. Вызов `ensureLegacyCutoffSet`.
- [ ] `POST /api/auth/exchange-seed-for-token` — для миграции: `{seed_phrase, device_id, platform, app_version}` → `{user: {id, data_version}, device_token}`. Покрыть существующим `authRateLimiter`. Вызов `ensureLegacyCutoffSet`.
- [ ] `GET /api/auth/legacy-status` — для web-баннера: возвращает `{legacy_auth_cutoff_at, all_migrated}`.
- [ ] `POST /api/auth/logout` — `UPDATE devices SET device_token_hash = NULL WHERE user_id AND device_id` (row остаётся для history).
- [ ] `resolveAuth` middleware (`server/src/middleware/auth.ts:84-115`) — приоритет 1: device_token Bearer → `devices.device_token_hash` DB-side lookup → `req.user_id`, `req.device_id`, throttled update `last_seen`. Приоритет 2: OAuth Bearer. Приоритет 3: legacy `x-user-id` **с проверкой cutoff** — если `users.legacy_auth_cutoff_at` в прошлом → 401 + audit log `legacy_rejected`.
- [ ] Socket.IO `io.use()` handshake middleware (см. `contracts/socketio-handshake.md`) — валидация `socket.handshake.auth.token`. Существующий `socket.on('auth', {userId, deviceId})` остаётся как legacy path с cutoff-проверкой, удаляется в фазе 7.
- [ ] Cleanup cron: daily `cleanupOrphanDevices` + `cleanupAuditLog`.
- [ ] Тесты: `auth.test.ts` расширить, `mcp-auth-service.test.ts` не ломать, новые `device-tokens.test.ts`, `legacy-cutoff.test.ts`, `auth-audit.test.ts`.
- [ ] Backend deployed → smoke test через `curl` вручную.

### Фаза 2 — Web/PWA (`recipe-scaler-web/recipe-scaler/`)

- [ ] **Sub-phase 2.0 — centralized `getAuthToken()` accessor** (`src/services/auth-token.ts`): единый accessor + `applyAuthHeaders()`. Codemod: заменить 30+ точек `localStorage.getItem('userId')` для auth header'ов. Проверка: `rg "localStorage.getItem\(['\"]userId"` возвращает только non-auth usage.
- [ ] `src/services/v2-auth-api.ts` — декодинг `device_token` из responses; новый метод `exchangeSeedForToken()`; `legacyStatus()` для баннера.
- [ ] `src/App.tsx` startup — миграционный шаг: если `localStorage.seed_phrase` есть и `localStorage.device_token` нет → `/exchange-seed-for-token` тихо. После успеха — `localStorage.removeItem('seed_phrase')`.
- [ ] `src/services/yjs-client.ts` — Socket.IO handshake с `auth: {token: deviceToken}`. Без `?token=` query. `emit("auth", {userId})` — только legacy fallback если нет token (grace).
- [ ] Logout cleanup — `localStorage.removeItem('device_token')`.
- [ ] **Баннер grace period** (`src/components/legacy-auth-banner.tsx`): запрос `legacy-status`, показ если `legacy_auth_cutoff_at` в будущем и `!all_migrated`. Текст i18n, кнопка «Подробнее». Скрывается после миграции всех активных устройств или после cutoff.
- [ ] E2E тесты: register → login → migrate → logout, плюс проверка баннера + Socket.IO handshake.

### Фаза 3 — iOS native (`recipe-scaler-native/`)

- [ ] `RecipeScalerCore/Auth/SharedAuthStore.swift` — добавить `token` property (Keychain, тот же service/account scheme что `userId`, тот же access group). Не трогать `userId` — он нужен для MCP bootstrap и debug.
- [ ] `RecipeScalerCore/Networking/APIClient.swift` — `configure(authToken:)` вызывается из `AuthService`. Bearer-branch в `buildRequest` уже есть. Никакого refresh-flow — токен бессрочный.
- [ ] `RecipeScalerNative/Services/AuthService.swift`:
  - `loginWithSeed`, `registerAuto` — декодят `device_token` из response → `SharedAuthStore.token = ...` → `apiClient.configure(authToken:)`.
  - `logout` — `SharedAuthStore.token = nil` + `apiClient.configure(authToken: nil)`.
  - `restoreAuthenticationState` — читает токен из `SharedAuthStore.token`, configure.
  - Migration на старте: если `SharedAuthStore.userId` есть и `SharedAuthStore.token == nil` → `/exchange-seed-for-token` (seed из app-local Keychain, который уже есть).
- [ ] `RecipeScalerNative/App/AppContainer.swift` — sync `APIClient.shared.configure(authToken:)` из `SharedAuthStore.token` (как уже делается для `userId`).
- [ ] `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` — Socket.IO handshake с `connectParams(["token": token])` (или `auth: { token }`). Legacy `socket.emit("auth", {userId})` удалить.
- [ ] Тесты: `SharedAuthStoreTests` расширить под `token`, `AuthServiceMigrationTests` для exchange-флоу.

### Фаза 4 — iOS extensions (`recipe-scaler-native/`)

- [ ] `ShareExtensionUI/ShareView.swift` — `submit()`: читает `SharedAuthStore.token` → `APIClient.shared.configure(authToken:)`. Discovery gate `if token == nil → notSignedIn`.
- [ ] `ActionExtension/ActionViewController.swift` — наследует ShareView, ничего явно не меняется.
- [ ] Ручное тестирование: Share Extension из Safari → recipe импортируется под правильным аккаунтом.

### Фаза 5 — Apple Watch (`recipe-scaler-native/`)

- [ ] `RecipeScalerNative/Services/WatchCredentialsBridge.swift` — `publish(token:)` в дополнение к `publish(userId:)`. Payload `transferUserInfo(["token": ...])`.
- [ ] `RecipeScalerNativeWatch/Services/WatchCredentialsStore.swift` — `token` property, watch-local Keychain.
- [ ] `RecipeScalerNativeWatch/App/RecipeScalerNativeWatchApp.swift` — init configure `APIClient.shared.configure(authToken:)` из `WatchCredentialsStore.token`.
- [ ] `RecipeScalerNativeWatch/Services/WatchTimerService.swift` — без изменений (использует `APIClient.shared`).
- [ ] Обновить контракт `specs/039-watchos-timers/contracts/watchconnectivity-creds.md` — теперь передаётся и `token`.
- [ ] Ручное тестирование: paired simulator, login на iPhone → timers на watch ходят под Bearer.

### Фаза 6 — Финал

## Фаза 6 — Финал и приёмка

### Тестовая пирамида

| Слой | Что | Где | Gate |
|---|---|---|---|
| **Unit** | `DeviceTokenService`, `legacy-cutoff`, `auth-headers`, `applyAuthHeaders`, `SharedAuthStore.token`, `WatchCredentialsStore.token`, `AuthService.loginWithSeed` (mock network) | `server/src/**/__tests__`, `RecipeScalerNative*/...Tests` | ≥90% coverage нового кода; CI green |
| **Integration** | `resolveAuth` middleware с разными комбинациями header'ов; Socket.IO handshake + cutoff-check; DB migration up/down | `server/src/**/__tests__` со spy'ами на supabase | Все test cases из `contracts/socketio-handshake.md` проходят |
| **E2E** | Cross-client сценарии (см. ниже) | `recipe-scaler/tests/e2e/*.playwright.ts`, XCUITest native | 8 обязательных сценариев ниже проходят |
| **Manual QA** | Share/Action Extension из Safari, Watch paired simulator, физический iPhone с prod build | Чек-лист ниже | Подписан QA-engineer'ом |

### Acceptance gate per phase

Каждая фаза считается **завершённой** только когда:

| Фаза | Критерий готовности |
|---|---|
| 1 (Backend) | `npm test` green + smoke-test в staging через `curl` (login/register/exchange/logout) возвращает ожидаемые shapes + audit log пишется + Socket.IO handshake работает с in-memory test client |
| 2 (Web) | `npm run e2e` green для sub-phase 2.4 + `rg "localStorage.getItem\(['\"]userId"` возвращает только non-auth usage + Lighthouse PWA score не упал |
| 3 (Native main app) | `xcodebuild test` green для `SharedAuthStoreTests` + `AuthServiceTests` + migration-test; build green для всех targets |
| 4 (iOS extensions) | Manual QA: Share из Safari импортирует под Bearer-аккаунтом; logout → notSignedIn |
| 5 (Watch) | Manual QA: paired simulator, login на iPhone → timers на watch под Bearer |
| 6 (Финал) | Все 8 E2E сценариев ниже + production rollout checklist |

### E2E сценарии (gate фазы 6)

- [ ] **E2E-1** (new user, zero state): register на web → `device_token` в localStorage → все запросы с Bearer → login на native с тем же seed → recipe через Share Extension → timer на watch → всё под Bearer.
- [ ] **E2E-2** (web migration): залогиненный web-user обновляет страницу → `exchangeSeedForToken` тихо → запросы переходят на Bearer → `seed_phrase` удаляется из localStorage.
- [ ] **E2E-3** (native migration): залогиненный native-user обновляет app → `restoreAuthenticationState` видит `userId` без token + есть seed → `exchangeSeedForToken` → token сохранён → запросы на Bearer.
- [ ] **E2E-4** (token revoke / logout): logout на device A → устройство A получает 401 на следующем запросе; device B с тем же `user_id` (если есть) продолжает работать.
- [ ] **E2E-5** (grace period end): device 1 мигрирует → cutoff установлен → баннер показывается на web + iOS (AC18) → имитируем `cutoff_at = NOW() - 1s` → device 2 с `x-user-id` получает 401 → экран входа.
- [ ] **E2E-6** (lost-seed fallback): очистка localStorage без logout → открываем app → экран входа → никаких неавторизованных exchange по public userId.
- [ ] **E2E-7** (Socket.IO handshake): подключение с `auth.token` → connected; без token на cutoff-истёкшем user → `auth_error` + disconnect; legacy `emit('auth')` на non-cutoff user ещё работает (transitional).
- [ ] **E2E-8** (audit log): каждый security event (`token_issued`, `token_revoked`, `cutoff_set`, `cutoff_triggered`, `legacy_rejected`) пишется в `auth_audit_log` с `{user_id, device_id, ip, user_agent, ts}`. Токен и seed **отсутствуют** в записях.

### Rollback-тесты

Каждый rollback-сценарий должен быть протестирован **до production rollout**:

- [ ] **R-1** Backend rollback (откат PR1): `legacy_auth_cutoff_at` уже установлен у некоторых user'ов → after rollback клиенты продолжают работать на `x-user-id` (cutoff не проверяется откатанным кодом). Down-migration: `UPDATE users SET legacy_auth_cutoff_at = NULL` идемпотентен.
- [ ] **R-2** Web rollback (откат PR2): `localStorage.device_token` есть, но старый client не знает про Bearer → шлёт `x-user-id` (если userId сохранён). Если userId удалён из-за миграции — экран входа. Acceptable.
- [ ] **R-3** Native rollback (откат PR3): `SharedAuthStore.token` сохранён в Keychain, но старый `AuthService` его не читает → шлёт `x-user-id`. Token остаётся как dead data в Keychain до re-login.
- [ ] **R-4** Socket.IO rollback: `io.use()` отклоняет подключения с token, но legacy `emit('auth')` ещё работает → клиенты fallback на legacy. Transitional design covers this.
- [ ] **R-5** Cutoff set + partial migration + emergency disable: командный сценарий — `"UPDATE users SET legacy_auth_cutoff_at = NULL"` для всех → grace восстанавливается → все устройства снова работают.

### Production rollout checklist

Перед активацией (когда все 3 PR замержены и задеплоены, но feature-flags ещё off):

- [ ] All 8 E2E сценариев проходят в staging.
- [ ] Audit log writes проверены в staging (`SELECT * FROM auth_audit_log ORDER BY ts DESC LIMIT 10`).
- [ ] Rate-limit на `/exchange-seed-for-token` проверен (5 req / 15 min / IP → 429).
- [ ] DB migration applied в prod, индексы построены, slow query log чист.
- [ ] `nginx`/reverse-proxy log-format маскирует `Authorization` (или подтверждено что access-log не пишет заголовки — см. N6).
- [ ] Monitor: alert на `auth_audit_log.legacy_rejected > N/min` (предупреждение о cutoff-DoS или массовых old-client 401).
- [ ] Monitor: alert на `auth.exchange.rate_limited > N/min` (брутфорс-попытки).
- [ ] Backup БД до activation.
- [ ] Notification plan готов: баннер в web + iOS (AC18), email/push — если есть.

После активации (feature-flags on, первый user мигрирует):

- [ ] Watch `auth_audit_log.token_issued` за первые 24 часа — корректный trend.
- [ ] Watch `devices.device_token_hash IS NOT NULL` count — растёт.
- [ ] Watch error rate (`5xx` auth endpoints) — не растёт.
- [ ] Watch Socket.IO connection count — не падает.
- [ ] Через 7 дней после первого cutoff: проверить E2E-5 (grace period end) на реальном user'е.

### Manual QA checklist (native + extensions + watch)

- [ ] **Share Extension** (Safari → Recipe Scaler): recipe импортируется под залогиненным аккаунтом; HTTP-запрос содержит `Authorization: Bearer` (verify в Charles Proxy / similar).
- [ ] **Action Extension**: тот же сценарий.
- [ ] **Share Extension after logout**: показывает `notSignedIn`, кнопка «Sign in with seed».
- [ ] **Watch (paired simulator)**: login на iPhone → watch получает `device_token` через WC bridge → timers ходят под Bearer; logout на iPhone → watch not-authorized.
- [ ] **Watch (no paired iPhone)**: показывает not-authorized; повторный login на iPhone → WC bridge доставляет token.
- [ ] **iOS Settings → Account**: баннер grace period (AC18) виден когда grace активен, скрывается после `all_migrated=true`.
- [ ] **Keychain attributes**: verify через `security` CLI на симуляторе/device что `token` Keychain item имеет `kSecAttrSynchronizable = false`.

### Security regression tests (continuous)

- [ ] `/exchange-seed-for-token` с одного IP > 5 раз/15 min → 429 + audit log `legacy_rejected`-style entry.
- [ ] Token enumeration attempt: random 32-byte tokens → 401 + audit log; rate-limit не срабатывает (только failed lookups).
- [ ] WS spoof: подключение с `emit('auth', {userId: 'someone-else'})` где cutoff истёк → disconnect. Pre-cutoff: подключается, но user может отозвать из future Active Sessions UI.
- [ ] `device_token_hash` UNIQUE constraint: insert duplicate hash → rejected DB-side.
- [ ] Audit log never contains `device_token` или `seed_phrase` substring (grep test).

### Linear / закрытие

- [ ] Закрыть Linear [MIK-117](https://linear.app/mikeozornin/issue/MIK-117/review-33-rasshireniya-autentificiruyutsya-tolko-plaintext-ne) с комментарием-ссылкой на PR'ы + ссылка на production rollout log.
- [ ] Коммиты в оба репо, отдельные PR'ы по плану.

## Документация, которая обновляется по ходу

- `recipe-scaler-web/llm/API.md` — обновить описание auth (device_token Bearer приоритет 1, OAuth Bearer приоритет 2, `x-user-id` приоритет 3 transitional).
- `recipe-scaler-web/AGENTS.md` — обновить секцию auth.
- `recipe-scaler-native/AGENTS.md` — обновить секцию Auth (Composition Root, `SharedAuthStore.token`).
- `specs/039-watchos-timers/contracts/watchconnectivity-creds.md` — **уже обновлён** in-place (spec 041 фаза 5).
- `review-kilo-glm-5.2-recipe-scaler-native.md` — отметить находки #1 и #33 как remediated.

## Декомпозиция для PR'ов

3 PR'а готовятся и деплоятся одним батчем (см. Cross-repo стратегия):

1. **PR1 — Backend** (`recipe-scaler-web`): DB migration + endpoints + middleware + Socket.IO + audit log + cleanup cron + server tests. Фолбэк `x-user-id` сохранён.
2. **PR2 — Web/PWA** (`recipe-scaler-web/recipe-scaler`): centralized `getAuthToken()` accessor (sub-phase 2.0) + localStorage migration + headers + Socket.IO client + баннер.
3. **PR3 — Native + extensions + watch** (`recipe-scaler-native`): SharedAuthStore.token + AuthService + APIClient + YjsSync + ShareView + WatchCredentialsBridge + iOS in-app баннер (AC18).

PR2 и PR3 независимы друг от друга, можно параллельно. Все три PR деплоятся вместе — grace period 7 дней покрывает race condition.

**PR4 — Post-cutoff cleanup** (фаза 7, отдельный PR после истечения последнего активного `legacy_auth_cutoff_at` всех user'ов): удалить legacy `socket.on('auth')`, legacy `x-user-id` middleware, legacy `data.user.id` из responses, legacy emit-fallback в клиентах.
