# План реализации: feature adoption tracker

**Spec**: [spec.md](./spec.md)
**Дата**: 2026-06-24 (rev. 2026-06-29)

## Декомпозиция

### Фаза A — Backend (минимум для появления данных)

1. **Миграция `user_feature_adoption`** — `recipe-scaler-web/server/migrations/2026_06_25_user_feature_adoption_public.sql` + `_dev.sql`. Таблица + индекс `(user_id)`. Существующая конвенция — см. `2026_06_13_add_timers_recipe_id_*.sql`.

2. **`feature-adoption-service.ts`** — в `server/src/services/`.
   - `mark(userId: string, feature: FeatureKey): Promise<void>` — `INSERT ... ON CONFLICT DO NOTHING`, логирует warning при ошибке.
   - `getReport(userId: string): Promise<FeatureAdoptionReport>` — один SELECT, маппинг в 11 булей (missing → false).
   - `FEATURE_KEYS` const + `FeatureKey` type.

3. **`POST /api/users/me/feature-adoption`** — в `routes/users.ts`. Body schema: `{ feature: z.enum(FEATURE_KEYS) }`. Idempotent insert.

4. **`GET /api/users/me/feature-adoption`** — там же. Owner-only через `requireUserId`. Заголовок `Cache-Control: private, max-age=60`.

5. **Server events wiring** — `featureAdoptionService.mark()` вызовы в 6 точках:
   - `recipe-service.ts`: `createRecipeFromUrl`, `createRecipeFromText` → `mark(userId, 'imported_recipe')`.
   - `recipe-service.ts`: `createRecipeInDatabase` → `mark(userId, 'created_recipe')`.
   - `telegram-service.ts`: `connectUser` после INSERT → `mark(userId, 'connected_telegram')`.
   - `mcp-auth-service.ts`: `issueTokens`/`exchangeCodeForToken` после INSERT в `oauth_access_tokens` → `mark(userId, 'connected_mcp_assistant')`.
   - `assistant-service.ts`: `respond`/`respondStream` после сохранения user-сообщения → `mark(userId, 'sent_assistant_message')`.

6. **Yjs listeners** — в `yjs-service.ts`:
   - При загрузке collection doc: подписаться на `folders` Y.Array. При первом `length > 0` → `mark(userId, 'created_collection')`, снять подписку.
   - При загрузке recipe doc: подписаться на `recipe` Y.Map поле `isPublic`. При первом `=== true` → `mark(userId, 'shared_recipe')`, снять подписку.
   - Все ошибки — лог warning, снять подписку (не death loop).

7. **Backfill скрипт** — `server/scripts/backfill-feature-adoption.ts`. Two-phase. Параметры `--apply`, `--only-sql`, `--only-emoji`, `--limit N`. Логирует прогресс каждые 100 пользователей.

8. **Unit-тесты** для `feature-adoption-service.ts`: мокаем `supabase`, проверяем `mark` (idempotent), `getReport` (11 ключей, missing → false). Интеграционный тест для endpoints (401 без auth, 200 с auth, 400 на невалидный feature).

### Фаза B — Native UI

9. **`FeatureAdoptionItem` enum** — `RecipeScalerNative/Models/FeatureAdoptionItem.swift`. CaseIterable, 11 кейсов, каждый знает свой i18n-ключ и raw value (feature key string).

10. **`AccountAPI.fetchFeatureAdoption()`** + DTO `FeatureAdoptionReportDTO` — расширение `AccountAPI.swift`. Возвращает `FeatureAdoptionReportDTO` с 11 optional Bool полями; геттер `value(for:)` возвращает `false` если nil.

11. **`FeatureAdoptionAPI.markFeatureAdoption(_:)`** в `RecipeScalerCore` + обёртка в `AccountAPI` — для `installed_native_app` (iPhone) и `installed_watch_app` (watch).

12. **`WatchFeatureAdoptionReporter`** — watch target; per-user UserDefaults, POST через `FeatureAdoptionAPI`.

13. **`FeatureAdoptionStore`** — `@Observable`, в `AppContainer`.
    - `@Published var report: FeatureAdoptionReport = .empty` (все false).
    - `loadFromCache()` — sync read из UserDefaults.
    - `refresh() async` — network fetch + update cache.
    - `markInstalledLocally()` — instant cache update для `installed_native_app`.

14. **`AuthService.markFeatureInstalled()`** — метод-обёртка:
    - Проверяет `UserDefaults.standard.bool(forKey: "feature-adoption.installed-reported")`.
    - Если не выставлен: обновляет локальный кэш `FeatureAdoptionStore` (instant UI), fire-and-forget `AccountAPI.markFeatureAdoption("installed_native_app")`.
    - При успехе — выставляет `feature-adoption.installed-reported = true`.
    - При ошибке — оставляет флаг не выставленным, повторит при следующем запуске.
    - Вызывается из `registerAuto()` и `loginWithSeed(_:)` после успешной авторизации. **Не** вызывается из `restoreAuthenticationState()`.

15. **`FeatureAdoptionSection` + `FeatureAdoptionRow`** — SwiftUI views. Размещается вверху `AccountView` выше блока профиля.
    - Row: иконка `checkmark.circle.fill` accent (done) или `circle` secondary (pending), текст из i18n.
    - Список из `FeatureAdoptionItem.allCases`.

16. **Pull-to-refresh** — добавить к `AccountView` `.refreshable { await store.refresh() }` (если ещё нет).

### Фаза C — i18n и тесты

17. **`Localizable.xcstrings`** — 11 ключей `account.feature-adoption.item.*` + `account.feature-adoption.title` (RU/EN).

18. **`LocalizationConsistencyTests`** — добавить новые ключи в проверку en+ru.

19. **Preview для `FeatureAdoptionSection`** — два стейта: all-done, all-pending; wide-digits для кольца прогресса (EN + RU locale).

20. **Verify-скрипт** `scripts/verify-feature-adoption.sh`: grep на новые файлы/строки + `xcodebuild build`.

## Deployment — dev-first стратегия

Прогон на dev-стенде **обязателен** перед production. План:

1. **Dev: миграция.** Применяем `2026_06_25_user_feature_adoption_dev.sql` на dev БД. Проверяем: `\d user_feature_adoption` показывает таблицу + индекс.
2. **Dev: backend deploy.** Запускаем dev-инстанс с новым кодом (events + listeners + endpoints).
3. **Dev: backfill dry-run.** `NODE_ENV=development bun server/scripts/backfill-feature-adoption.ts --env .env.dev` (без `--apply`) — смотрим отчёт, какие флаги и скольким юзерам проставились бы.
4. **Dev: backfill apply Phase 1 (SQL).** `--only-sql --apply`. Проверяем метрики: `SELECT feature, COUNT(*) FROM user_feature_adoption GROUP BY feature;`
5. **Dev: backfill apply Phase 2 (Yjs).** Полный `--apply`. Метрики те же.
6. **Dev: API smoke.** Через curl/postman: `GET /api/users/me/feature-adoption` (нужен валидный dev userId в header), проверяем что 10 ключей возвращаются. `POST /feature-adoption { installed_native_app }` дважды — убеждаемся что `ON CONFLICT DO NOTHING` отрабатывает (1 запись). Watch: первое открытие с сессией → `installed_watch_app`.
7. **Dev: live event smoke.** Создаём рецепт через `POST /api/recipes` → проверяем что `created_recipe` появился. Импортируем по URL → `imported_recipe`. Подключаем Telegram → `connected_telegram`. Пишем в ассистент → `sent_assistant_message`. Создаём коллекцию через Yjs → ждём listener → `created_collection`. Делаем рецепт публичным через Yjs → ждём listener → `shared_recipe`.
8. **Dev: native UI smoke.** Билдим native против dev-сервера, проходим flow авторизации (register-auto или login-with-seed) → `installed_native_app` загорается.
9. **Production deploy** — только после зелёного smoke на dev. Тот же порядок: миграция → backend → backfill (dry-run → Phase 1 → Phase 2) → native build в TestFlight/App Store.
10. **Production post-deploy check** — повторный dry-run backfill (должен показать 0 новых записей, всё уже проставлено). Метрики `SELECT feature, COUNT(*) ... GROUP BY feature` сравниваем с ожидаемыми (из dev dry-run, отмасштабированные).

### Rollback

- **Миграция** — `DROP TABLE IF EXISTS user_feature_adoption;` (без каскадных эффектов, отдельная таблица).
- **Backend events** —.fire-and-forget, не блокируют бизнес-операции. Если событие падает, бизнес всё равно работает. Для отката достаточно убрать `featureAdoptionService.mark()` вызовы.
- **Yjs listeners** — могут быть отключены через env flag `FEATURE_ADOPTION_YJS_LISTENERS=false` (по умолчанию true).
- **Native UI** — раздел можно скрыть через `UserDefaults` feature flag (или через возвращаемый набор ключей с сервера — если ключей меньше ожидаемого, раздел не показывается).

## Риски

- **Yjs listener не срабатывает для неактивных документов** — если doc ни разу не загружался после деплоя, флаг не проставится. Mitigation: периодический incremental backfill (раз в неделю) для активных пользователей.
- **`installed_native_app` идемпотентность на устройстве** — если пользователь логинится/логаутится много раз, мы делаем `markFeatureInstalled()` один раз за устройство (через `feature-adoption.installed-reported` флаг). Но если юзер сносит app и ставит заново — флаг сбрасывается, запрос уходит повторно. Это нормально — `ON CONFLICT DO NOTHING` на сервере отрабатывает.
- **Производительность backfill Phase 2** — для ~тысяч пользователей итеративный Yjs decode может занять десятки минут. Mitigation: батчинг, прогресс-лог, возможность прервать и продолжить (idempotent insert'ы).
- **Listener memory leak** — если забыть снять подписку после первого события → на каждое следующее действие в doc будет попытка INSERT (ON CONFLICT спасает, но CPU тратится). Mitigation: явно `unobserve()` после первого триггера, unit-тест на «listener стреляет один раз».

## Файлы

### Backend (новые)

- `recipe-scaler-web/server/migrations/2026_06_25_user_feature_adoption_public.sql`
- `recipe-scaler-web/server/migrations/2026_06_25_user_feature_adoption_dev.sql`
- `recipe-scaler-web/server/src/services/feature-adoption-service.ts`
- `recipe-scaler-web/server/src/__tests__/feature-adoption-service.test.ts`
- `recipe-scaler-web/server/scripts/backfill-feature-adoption.ts`

### Backend (правки)

- `recipe-scaler-web/server/src/routes/users.ts` — 2 endpoints (GET + POST)
- `recipe-scaler-web/server/src/services/recipe-service.ts` — 2 event hooks
- `recipe-scaler-web/server/src/services/telegram-service.ts` — 1 event hook
- `recipe-scaler-web/server/src/services/mcp-auth-service.ts` — 1 event hook
- `recipe-scaler-web/server/src/services/assistant-service.ts` — 1 event hook
- `recipe-scaler-web/server/src/services/yjs-service.ts` — 2 Yjs listeners

### Native (новые)

- `recipe-scaler-native/RecipeScalerCore/Networking/FeatureAdoptionAPI.swift`
- `recipe-scaler-native/RecipeScalerCore/Networking/FeatureAdoptionClientFeature.swift`
- `recipe-scaler-native/RecipeScalerNative/Models/FeatureAdoptionItem.swift`
- `recipe-scaler-native/RecipeScalerNative/Services/FeatureAdoptionStore.swift`
- `recipe-scaler-native/RecipeScalerNative/Utils/FeatureAdoptionRingLabelLayout.swift`
- `recipe-scaler-native/RecipeScalerNative/Views/FeatureAdoptionDetailView.swift`
- `recipe-scaler-native/RecipeScalerNativeWatch/Services/WatchFeatureAdoptionReporter.swift`
- `recipe-scaler-native/RecipeScalerNativeTests/FeatureAdoptionRingLabelLayoutTests.swift`

### Native (правки)

- `recipe-scaler-native/RecipeScalerNative/Services/AccountAPI.swift` — `fetchFeatureAdoption` + `markFeatureAdoption` (делегат в Core)
- `recipe-scaler-native/RecipeScalerNative/Services/AuthService.swift` — `markFeatureInstalled()`, `clearForLogout` для adoption cache
- `recipe-scaler-native/RecipeScalerNative/Views/AccountView.swift` — ссылка на `FeatureAdoptionDetailView`, `.refreshable`
- `recipe-scaler-native/RecipeScalerNative/App/AppContainer.swift` — `FeatureAdoptionStore`, `stopForLogout`
- `recipe-scaler-native/RecipeScalerNativeWatch/Services/WatchCredentialsStore.swift` — adoption trigger / purge на `set(_:)`
- `recipe-scaler-native/RecipeScalerNative/Resources/Localizable.xcstrings` — 10 items + footnotes + title
- `recipe-scaler-native/RecipeScalerNativeTests/LocalizationConsistencyTests.swift` — расширить
- `recipe-scaler-native/scripts/verify-feature-adoption.sh` — grep watch + 10-й ключ

### Documentation

- `recipe-scaler-web/llm/API.md` — добавить `feature-adoption` endpoints в owner-only contract
- `recipe-scaler-web/llm/CHANGELOG.md` — backfill флаги для существующих пользователей

## Open questions

1. **Pull-to-refresh в `AccountView`** — есть ли уже? Если нет — добавляем в рамках Фазы B. Проверить при реализации.
2. **Yjs listener в `yjs-service.ts`** — где именно навешивать observeDeep? Проверить структуру `yjs-service.ts` перед имплементацией; возможно потребуется переработать pattern подписок.
3. **Backfill: использовать `bun` или `tsx`/`ts-node`?** — в проекте используется `bun` (см. `migrate-has-steps.ts`). Оставить `bun`.
4. **Incremental backfill** — стоит ли автоматизировать через cron (раз в неделю)? В v1 — ручной запуск; cron в следующей итерации если будут жалобы на stale флаги.
