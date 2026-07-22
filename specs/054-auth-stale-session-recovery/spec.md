# Спецификация: Auth stale-session recovery + sync_error.truncated_collection

**Дата**: 2026-07-16
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

1. При обнаружении на cold start, что сохранённый пользователь больше не
   существует на сервере — полностью зачищать локальную сессию и показывать
   `AuthView` для повторного входа (silent register-auto **не** делаем —
   пользователь должен осознанно выбрать: новый аккаунт или вход с seed).
2. Добавить `truncated_collection` в `SyncErrorCode` как typed case, чтобы
   обработка шла по явной ветке вместо generic-fallback.

## Non-goals

- **Silent register-auto** — намеренно отказались (см. развилка ниже).
  Потеря рецептов без объяснения хуже, чем один экран входа.
- **Миграция нативки на modern `sync_step1`/`sync_step2` handshake** — отдельная
  задача; сейчас нативка на legacy `load_document`, и этот spec это не меняет.
- **Active Sessions UI**, logout-on-revoke — covered spec 041.
- **Web parity для collection-recovery** — в нативке не возникает тот же
  saturated-SV trap; в этой спеке только typed error code.

## Развилки, зафиксированные при обсуждении

- **Поведение при 404 от `/api/settings`**: показать `AuthView` (выбрано из
  вариантов silent-register-auto / show-AuthView / alert-then-AuthView).
  Обоснование: silent-create-new-user теряет все рецепты пользователя без
  объяснения; явный экран входа даёт выбор.

## User stories

1. Пользователь открывает app после серверного cutover / удаления аккаунта →
   app не зависает на пустом списке рецептов, а через короткий health-check
   обнаруживает 404 → зачищает локальные credentials → показывает `AuthView`.
2. Пользователь видит `AuthView`, выбирает «Создать новый аккаунт» или входит
   с seed phrase с другого устройства → sync поднимается заново.
3. Пользователь с урезанной локальной коллекцией (edge case при будущей
   миграции на modern handshake) → сервер эмитит `truncated_collection` →
   нативка переходит в typed-ветку `SyncErrorCode.truncatedCollection` →
   перезагружает коллекцию через `load_document` (legacy path) без ошибок в UI.

## Требования

### Функциональные

- **F1.** На cold start, после `AuthService.restoreAuthenticationState`, если
  есть сохранённый `userId` — выполнить health-check `GET /api/settings`.
  Запрос должен идти **до** старта sync/timer/socket (чтобы не поднять
  обречённую на 401 сессию).
- **F2.** При 404 на `GET /api/settings`:
  - Очистить `SharedAuthStore` (`userId`, `token`).
  - Удалить seed phrase из app-local Keychain.
  - Сбросить `AuthService.userId`, `.token`, `.isAuthenticated`.
  - Сбросить `APIClient.shared` auth config.
  - Уведомить watch через `WatchCredentialsBridge.shared.purge()`.
  - Не вызывать server-side logout (user уже не существует).
- **F3.** При 5xx / network error на health-check — **не** зачищать сессию,
  продолжить загрузку с сохранённым userId (временный сбой сервера не должен
  выкидывать пользователя).
- **F4.** При 401 на health-check — то же поведение, что при 404 (токен
  отозван, но пользователь может существовать; без seed восстановить нельзя
  → показать AuthView, чтобы пользователь мог войти с другого устройства).
- **F5.** Health-check не блокирует UI дольше 5 секунд; при таймауте —
  продолжить загрузку с сохранённым userId (soft-fail).
- **F6.** DEBUG simulator с auto-login (`debugUserId`) пропускает health-check
  — девайс разработки не должен ловить 404 при отладке на несуществующем ID.
- **F7.** `SyncErrorCode` добавляет case `truncatedCollection` с rawValue
  `"sync.error.truncated-collection"`. `handleSyncError` для этого case:
  - Не показывать пользователю ошибку (collection recovery — внутренний
    процесс, не user-facing).
  - Перевести коллекцию в режим reload: `hasRequestedCollectionLoad = false`
    + `loadCollectionDocument()` (существующий `reloadCollectionFromServer`).
  - Не инкрементить unsynced-флаги.
- **F8.** Локализованная строка `sync.error.truncated-collection` всё равно
  добавляется в `Localizable.xcstrings` (на случай если в будущем ветка
  решит показывать user-facing alert; текущая реализация не использует).

### Нефункциональные

- **N1.** Health-check — единственный дополнительный сетевой запрос на cold
  start. Не должен ощутимо увеличивать perceived launch time (таргет < 500 ms
  в нормальных условиях, soft-fail на 5s).
- **N2.** Все лог-сообщения используют `AppLog.info(.app, ...)` с event-name
  dot-style (`stale_session_detected`, `stale_session_cleared`,
  `health_check_timeout`, `health_check_network_error`). Никаких PII в логах.
- **N3.** Тесты: unit-тест на 404 → состояние сброшено; unit-тест на 5xx →
  состояние сохранено; unit-тест на таймаут → состояние сохранено.

## Downstream consumers (изменяемое состояние)

- `AuthService.userId`, `.token`, `.isAuthenticated` — читают: `ContentView`
  (`isAuthenticated`, `effectiveUserId`), `AccountSettingsViewModel`,
  `WatchCredentialsBridge`, extensions через `SharedAuthStore`.
- `SharedAuthStore` — читают: extensions (Share, Action), watch app, AppIntents,
  `APIClient.shared` (cross-process sync при launch).
- `SyncErrorCode.truncatedCollection` — читает только `handleSyncError` в
  `YjsSyncService`.

## Positive invariants (для тестов)

| Эффект функции / API | Инвариант | Где проверять |
|---------------------|----------|---------------|
| Health-check 404 → wipe | После вызова `SharedAuthStore.userId == nil`, `SharedAuthStore.token == nil`, `AuthService.isAuthenticated == false` | `AuthServiceStaleSessionTests` |
| Health-check 5xx → keep | После вызова `SharedAuthStore.userId` сохранён, `AuthService.isAuthenticated == true` | `AuthServiceStaleSessionTests` |
| Health-check timeout → keep | После 5s таймаута состояние не изменилось | `AuthServiceStaleSessionTests` |
| `truncated_collection` в sync_error | `SyncErrorCode.from(code: "sync.error.truncated-collection") == .truncatedCollection` | `SyncErrorCodeTests` |

## Acceptance criteria

- [ ] AC1. На cold start с сохранённым `userId`, который не существует на
  сервере (404 на `/api/settings`), `AuthService` полностью зачищает
  сессию и `isAuthenticated == false`.
- [ ] AC2. На 5xx / network error сессия сохраняется, sync стартует с
  сохранённым userId.
- [ ] AC3. На таймауте health-check (>5s) сессия сохраняется.
- [ ] AC4. DEBUG simulator с `debugUserId` не делает health-check.
- [ ] AC5. `SyncErrorCode.from(code: "sync.error.truncated-collection")`
  возвращает `.truncatedCollection`.
- [ ] AC6. `handleSyncError(.truncatedCollection, ...)` не устанавливает
  `syncErrorMessage` и не инкрементит unsynced-флаги; вызывает
  `reloadCollectionFromServer()`.
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
- **R2.** Race condition: health-check + параллельный socket connect. Если
  socket успел подключиться с валидным токеном до завершения health-check —
  очистка сессии оставит socket в зависшем состоянии. **Mitigation**:
  health-check выполняется **до** `sync.start` в `AppContainer.bootstrap`,
  сокет ещё не поднят.
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
