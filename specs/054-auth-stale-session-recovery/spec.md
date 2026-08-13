# Спецификация: Auth stale-session recovery + sync_error.truncated_collection

**Дата**: 2026-07-16 (правка порядка probe: 2026-08-13)
**Статус**: 🟡 В работе
**Связанные коммиты web**: `c953b9ff` (auth 404 session clear), `2c7e081f` (collection self-heal)

## Контекст и мотивация

16 июля 2026 прошёл Postgres cutover (`d0958b1b`). После миграции БД возможны
два класса устройств с устаревшей локальной сессией:

1. **userId в Keychain ссылается на удалённого пользователя** (dump/restore
   потерял строку, или админ удалил аккаунт). На любой protected endpoint
   приходит 404. В web это уже починено в `c953b9ff` — локальная сессия
   зачищается полностью (`userId`, `seed_phrase`, `device_token`,
   register-auto block flags, session-revoked flag), после чего показывается
   `AuthView`. В нативке `AccountAPI.fetchUserSettings()` (`AccountAPI.swift:183`)
   просто бросает ошибку, `AccountSettingsViewModel.refresh` глотает её через
   `try?`, а `AuthService.restoreAuthenticationState` (`AuthService.swift:166`)
   восстанавливает сессию без проверки существования пользователя на сервере.
   Socket.IO handshake с невалидным `device_token` вернёт `unauthorized`, sync
   не поднимется, UI зависнет на пустом состоянии.

2. **Локальная коллекция Yjs имеет hard-deletes при saturated state vector**
   (Safari eviction / старые версии с legacy full-push-on-connect). В web
   добавлен `collection-recovery.ts` (`2c7e081f`) — при обнаружении truncated
   collection клиент дропает doc и ре-хендшейкается с empty SV. Нативка сейчас
   использует legacy `load_document` (`YjsSyncService.swift:1638`), который
   всегда отдаёт canonical state, поэтому saturated-SV trap напрямую не
   возникает. **Но**: сервер всё равно эмитит `sync_error` с
   `code: 'truncated_collection'`, а `SyncErrorCode` о нём не знает
   (`SyncErrorCode.swift:32-37`) → код падает в `.generic`, который через 5
   секунд ре-эмитит `load_document`. Коллекция в итоге восстановится, но
   ценой лишнего цикла и логов ошибок.

## Цель

1. На cold start сразу показывать локальные рецепты. Если сохранённый
   пользователь больше не существует на сервере — после фонового health-check
   полностью зачищать локальную сессию и показывать `AuthView` (silent
   register-auto **не** делаем).
2. Добавить `truncated_collection` в `SyncErrorCode` как typed case, чтобы
   обработка шла по явной ветке вместо generic-fallback.

## Non-goals

- **Silent register-auto** — намеренно отказались (см. развилка ниже).
  Потеря рецептов без объяснения хуже, чем один экран входа.
- **Миграция нативки на modern `sync_step1`/`sync_step2` handshake** — выполнена
  отдельным эпиком (Binary Yjs sync, 2026-08-07, см. `docs/DECISIONS.md`).
  Нативка использует новый протокол как основной путь; per-request probe
  (~5s) падает обратно на legacy `load_document` без постоянного pinning.
  `truncatedCollection` recovery: drop local collection + empty-SV `sync_step1`
  (как web), не plain reload с saturated SV.
- **Active Sessions UI**, logout-on-revoke — covered spec 041.
- **Web parity для collection-recovery** — в нативке не возникает тот же
  saturated-SV trap; в этой спеке только typed error code.

## Развилки, зафиксированные при обсуждении

- **Поведение при 404 от `/api/settings`**: показать `AuthView` (выбрано из
  вариантов silent-register-auto / show-AuthView / alert-then-AuthView).
  Обоснование: silent-create-new-user теряет все рецепты пользователя без
  объяснения; явный экран входа даёт выбор.
- **Порядок health-check vs локальные снимки** (2026-08-13): probe **не**
  блокирует `sync.start`. Ранний вариант ждал `GET /api/settings` до старта
  sync (чтобы не поднять сокет с мёртвой сессией). В авиарежиме это давало
  ~60 с «Loading recipes…» при живых офлайн-данных. Выбрано: сразу грузить
  SQLite, probe в фоне; при 404/401 — wipe + container teardown (сокет, если
  успел подняться, останавливается). Transient (сеть/таймаут) сессию не трогает.

## User stories

1. Пользователь открывает app после серверного cutover / удаления аккаунта →
   локальный список может мелькнуть из кэша, затем health-check получает 404 →
   зачищаются локальные credentials → `AuthView`.
2. Пользователь открывает app в авиарежиме (офлайн cold start) → список
   рецептов показывается из локальных Yjs-снимков сразу, без ожидания
   сетевого таймаута. Health-check в фоне завершается `.transient`, сессия
   сохраняется.
3. Пользователь видит `AuthView`, выбирает «Создать новый аккаунт» или входит
   с seed phrase с другого устройства → sync поднимается заново.
4. Пользователь с урезанной локальной коллекцией (edge case при будущей
   миграции на modern handshake) → сервер эмитит `truncated_collection` →
   нативка переходит в typed-ветку `SyncErrorCode.truncatedCollection` →
   перезагружает коллекцию через `load_document` (legacy path) без ошибок в UI.

## Требования

### Функциональные

- **F1.** На cold start, после `AuthService.restoreAuthenticationState`, если
  есть сохранённый `userId` — `AppContainer.bootstrap(userId:)` планирует
  health-check `GET /api/settings` **в фоне** (`scheduleStaleSessionHealthCheckIfNeeded`)
  и **не** `await` его до `sync.start` / `loadLocalSnapshots()`. Список рецептов
  (`isLocalDataLoaded`) не зависит от этого HTTP. При подтверждённом 404/401
  `performStaleSessionHealthCheck` делает wipe; container teardown останавливает
  sync/socket, если они уже стартовали. Probe одноразовый на процесс
  (`didPerformStaleSessionHealthCheck`); отменяется на logout.
- **F2.** При 404 на `GET /api/settings`:
  - Очистить `SharedAuthStore` (`userId`, `token`).
  - Удалить seed phrase из app-local Keychain.
  - Сбросить `AuthService.userId`, `.token`, `.isAuthenticated`.
  - Сбросить `APIClient.shared` auth config.
  - Уведомить watch через `WatchCredentialsBridge.shared.purge()`.
  - Вызвать container teardown (`clearSessionForLogout` + `stopForLogout`).
  - Не вызывать server-side logout (user уже не существует).
- **F3.** При 5xx / network error на health-check — **не** зачищать сессию,
  продолжить работу с сохранённым userId и уже загруженными локальными снимками
  (временный сбой / авиарежим не должен выкидывать пользователя).
- **F4.** При 401 на health-check — то же поведение, что при 404 (токен
  отозван, но пользователь может существовать; без seed восстановить нельзя
  → показать AuthView, чтобы пользователь мог войти с другого устройства).
- **F5.** Health-check **не блокирует** UI: spinner «Loading recipes…» снимается
  после локальных снимков, даже если probe ещё висит на `URLSession`. Таймаут /
  сеть → `.transient` (F3). Отдельный 5-секундный client timeout для этого
  запроса не требуется для perceived launch.
- **F6.** E2E (`E2E_OVERRIDE_USER_ID` + token) **пропускает** probe (свежий
  пользователь). DEBUG simulator auto-login probe **не** пропускает: при wipe
  на симуляторе (не XCTest) credentials реинжектятся и bootstrap перезапускается,
  потому что `ContentView` на симуляторе не показывает `AuthView`.
- **F7.** `SyncErrorCode` добавляет case `truncatedCollection` с rawValue
  `"sync.error.truncated-collection"`. `handleSyncError` для этого case:
  - Не показывать пользователю ошибку (collection recovery — внутренний
    процесс, не user-facing).
  - Drop local collection (in-memory + SQLite snapshot + offline queue) и
    `sync_step1` с пустым state vector (`recoverCollectionFromServer`) —
    plain reload с saturated SV после Binary Yjs sync no-op'ит.
  - Не инкрементить unsynced-флаги.
- **F8.** Локализованная строка `sync.error.truncated-collection` всё равно
  добавляется в `Localizable.xcstrings` (на случай если в будущем ветка
  решит показывать user-facing alert; текущая реализация не использует).

### Нефункциональные

- **N1.** Health-check не входит в критический путь first paint списка рецептов.
  Perceived launch = время `loadLocalSnapshots()`, не RTT `/api/settings`.
- **N2.** Все лог-сообщения используют `AppLog.info(.app, ...)` с event-name
  dot-style (`stale_session_detected`, `stale_session_cleared`,
  `stale_session_check_ok`). Никаких PII в логах.
- **N3.** Тесты: 404 → wipe; 5xx/network → keep; планирование probe не ждёт
  завершения HTTP (`AppContainerTests`).

## Downstream consumers (изменяемое состояние)

- `AuthService.userId`, `.token`, `.isAuthenticated` — читают: `ContentView`
  (`isAuthenticated`, `effectiveUserId`), `AccountSettingsViewModel`,
  `WatchCredentialsBridge`, extensions через `SharedAuthStore`.
- `YjsSyncService.isLocalDataLoaded` / `collectionEntries` — читают
  `RecipeListView`, `CollectionsRootView` (spinner vs список). Не ждут probe.
- `SharedAuthStore` — читают: extensions (Share, Action), watch app, AppIntents,
  `APIClient.shared` (cross-process sync при launch).
- `SyncErrorCode.truncatedCollection` — читает только `handleSyncError` в
  `YjsSyncService`.

## Positive invariants (для тестов)

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| Health-check 404 → wipe | После вызова `SharedAuthStore.userId == nil`, `SharedAuthStore.token == nil`, `AuthService.isAuthenticated == false` | `AuthServiceStaleSessionTests` |
| Health-check 5xx / network → keep | После вызова `SharedAuthStore.userId` сохранён, `AuthService.isAuthenticated == true` | `AuthServiceStaleSessionTests` |
| Schedule probe не блокирует caller | После `scheduleStaleSessionHealthCheckIfNeeded` сессия ещё жива, пока висящий probe не завершён | `AppContainerTests` |
| Фоновый 404 → wipe | После resume probe `.userMissing` сессия зачищена | `AppContainerTests` |
| `truncated_collection` в sync_error | `SyncErrorCode.from(code: "sync.error.truncated-collection") == .truncatedCollection` | `SyncErrorCodeTests` |

## Acceptance criteria

- [ ] AC1. На cold start с сохранённым `userId`, который не существует на
  сервере (404 на `/api/settings`), `AuthService` полностью зачищает
  сессию и `isAuthenticated == false` (после завершения фонового probe).
- [ ] AC2. На 5xx / network error / авиарежим сессия сохраняется; локальные
  рецепты уже показаны (sync стартовал, не дожидаясь probe).
- [ ] AC3. Висящий / долгий health-check не держит UI на `recipe.list.loading`.
- [ ] AC4. E2E override пропускает probe. DEBUG simulator при wipe
  реинжектит auto-login credentials (вне XCTest).
- [ ] AC5. `SyncErrorCode.from(code: "sync.error.truncated-collection")`
  возвращает `.truncatedCollection`.
- [ ] AC6. `handleSyncError(.truncatedCollection, ...)` не устанавливает
  `syncErrorMessage` и не инкрементит unsynced-флаги; вызывает
  `recoverCollectionFromServer()` (drop local + empty-SV `sync_step1`).
- [ ] AC7. Локализованная строка `sync.error.truncated-collection` добавлена
  в `Localizable.xcstrings` (ru + en).
- [ ] AC8. `xcodebuild build` green для основного target.
- [ ] AC9. `xcodebuild test` green для новых и затронутых тест-классов.

## Риски

- **R1.** False-positive 404 при кратковременной деградации сервера →
  пользователь выкидывается на AuthView без причины. **Mitigation**: сервер
  возвращает 404 только для несуществующего user; для системных ошибок это 5xx.
  Дополнительно: health-check идёт после того, как socket уже мог подключиться;
  если сервер вернул 5xx — не выкидываем.
- **R2.** Race: probe ещё идёт, а `sync.start` уже поднял сокет. При 404/401
  wipe должен остановить уже живой sync, иначе останется сессия на экране и
  сокет с мёртвым токеном. **Mitigation**: `wipeLocalSession` вызывает
  `performInvalidationTeardown` (sync stop + `stopForLogout`); task probe
  отменяется на logout; после `await` сверяется `expectedUserId` /
  `Task.isCancelled`, чтобы поздний 404 не стёр уже другую сессию.
- **R3.** Добавление `truncatedCollection` ломает `Switch SyncErrorCode` в
  других местах. **Mitigation**: exhaustive switch в Swift форсирует
  coverage на этапе компиляции.

## Ссылки

- Web коммит: [c953b9ff](https://recipe-scaler.ru/commit/c953b9ff) — auth 404
- Web коммит: [2c7e081f](https://recipe-scaler.ru/commit/2c7e081f) —
  collection self-heal
- Native spec 041 — auth device tokens
- Native spec 031 — typed sync error codes
- `specs/shared/sync-protocol.md` (web repo) — truncation guard, sync_error
