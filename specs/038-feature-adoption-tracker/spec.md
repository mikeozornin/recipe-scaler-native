# Спецификация: раздел «Сделанные вещи» в настройках (feature adoption tracker)

**Ветка**: `038-feature-adoption-tracker`
**Дата**: 2026-06-24 (rev. 2026-06-29)
**Статус**: 🟡 На стадии plan
**Зависимости**: `013-account-settings` (Profile, `AccountAPI`, `AuthService`), backend auth/`requireUserId`, `recipe-service`, `assistant` routes, `telegram-service`, `mcp-auth-service`, `yjs-service`
**Эталон**: новый раздел вверху Profile (native iOS), серверная таблица + endpoint отчёта + backfill скрипт + live events

## Контекст

В приложении есть много фич, которые пользователь не сразу обнаруживает: импорт рецепта, ассистент, коллекции, Telegram, MCP, список покупок. Раздел «Насколько вы освоили Recipe Scaler» в секции аккаунта показывает галочки по сделанным действиям и мягко подсвечивает, что ещё осталось попробовать.

Список действий зафиксирован продуктом (11 пунктов). Расширение списка — через добавление новых feature-ключей, без миграций (только данные).

### Архитектурное решение (после аудита БД)

Аудит `recipe-scaler-web/server/src/database/migrations.sql` показал: в SQL-таблице `recipes` колонки `source_url`, `original_recipe_link`, `is_public` **отсутствуют** — эти данные живут только в Yjs doc (`originalRecipeLink`, `isPublic` в `Y.Map('recipe')`, `folders` в collection doc). Дроп колонок выполнен в `migrations.sql:111–126`.

Поэтому read-pass «посчитать флаг на лету из SQL» невозможен для 5 из 9 флагов (`imported_recipe`, `created_recipe` partial, `shared_recipe`, `created_collection`, `used_shopping_list`). Архитектура — **single source of truth = таблица `user_feature_adoption`**:

- **Backfill скрипт** один раз проходит по всем пользователям и заполняет таблицу (для SQL-deriveable флагов — одним пакетом; для Yjs-derived — через `yjsService` итеративно).
- **Live events** — при каждом новом действии сервер (или Yjs listener) пишет в таблицу через `INSERT ... ON CONFLICT DO NOTHING`.
- **GET endpoint** — простой `SELECT` из таблицы, без read-pass на лету.

### Scope: только нативка

Раздел делается только в нативном iOS приложении. В вебе UI не появляется. Backend разделяемый —endpoint'ами могут пользоваться любые клиенты в будущем, но UI только native.

## Цель

Раздел вверху Profile с 11 чек-поинтами. Состояние синхронизируется между устройствами (не CRDT — простой read на холодном старте + pull-to-refresh). Сервер — единый источник правды через `user_feature_adoption` таблицу.

## Пользовательские сценарии

### Список отслеживаемых действий (11 пунктов)

| Feature key | Заголовок (i18n) | Когда засчитывается | Кто пишет в таблицу |
|-------------|------------------|---------------------|---------------------|
| `installed_native_app` | «Установлено приложение» | Успешная авторизация в native app (seed-фраза ИЛИ register-auto для нового юзера) | iPhone native клиент через POST |
| `installed_watch_app` | «Установлено приложение на часах» | Первое открытие watch app с активной сессией (`userId` на часах) | watchOS клиент через POST |
| `created_recipe` | «Записан рецепт» | Создан рецепт (через импорт, вручную POST `/api/recipes`, через распознавание текста, через Telegram-бота) | Server event в recipe-service create path |
| `used_shopping_list` | «Записали что купить» | Появился хотя бы один item в shopping-list doc пользователя (`items.length > 0`) | Server-side Yjs listener на shopping-list doc |
| `imported_recipe` | «Импортирован рецепт» | Успешный import URL/text/photo (endpoint `/api/v2/recipes/:id/parse` или аналог) | Server event в import handler |
| `created_collection` | «Создана коллекция» | Появилась хотя бы одна папка в collection doc пользователя (`folders.length > 0`) | Server-side Yjs listener на collection doc |
| `sent_assistant_message` | «Пообщались с ассистентом» | Хотя бы одно `assistant_messages` с `role='user'` | Server event в assistant respond handler |
| `connected_telegram` | «Подключен Телеграм» | `telegram_connections` запись существует | Server event в telegram connect handler |
| `connected_mcp_assistant` | «Подключен внешний ассистент» | Хотя бы один `oauth_access_tokens` для пользователя (любой, включая истекшие — TTL 1 час, иначе флаг не засчитывался бы через час после подключения) | Server event в mcp-auth-service при issueToken |
| `shared_recipe` | «Пошарен рецепт» | Хотя бы один рецепт с `isPublic=true` в Y.Map | Server-side Yjs listener на recipe doc |
| `named_with_emoji` | «Назвали рецепт или коллекцию с эмодзи» | После успешного сохранения текущего названия рецепта или активной папки с ведущим эмодзи | Server-side Yjs save path; backfill для текущих документов |

### US1 — Просмотр раздела (P1)

**Когда** пользователь открывает вкладку Profile, **тогда** в секции «Аккаунт» (между данными аккаунта и публичными профилями) видна строка-ссылка с заголовком `account.feature-adoption.title` и счётчиком `N / 11`. На экране детализации — многострочный заголовок в контенте (без обрезки в navigation bar), кольцевой прогресс `N из M` и список строк со статусными галочками (`checkmark` primary при выполнено, `circle` secondary при невыполнено). Под каждой строкой — onboarding-подпись footnote (`.appFootnote()`, secondary color) для контекста.

### US2 — Синхронизация между устройствами (P1)

**Когда** пользователь выполнил действие на устройстве A (например, импорт рецепта), **тогда** после pull-to-refresh в Profile на устройстве B галочка появляется.

### US3 — `installed_native_app` триггер (P1)

**Когда** пользователь впервые входит в native app — либо через register-auto (новый юзер), либо через `loginWithSeed` (существующий юзер впервые ставит нативку), **тогда** клиент отправляет `POST /api/users/me/feature-adoption { feature: "installed_native_app" }` сразу после успешной авторизации. При повторных входах на том же устройстве запрос не повторяется (флаг уже выставлен локально и на сервере).

### US4 — Обновление без перезапуска (P2)

**Когда** пользователь только что выполнил действие в текущей сессии (например, отправил первое сообщение ассистенту), **тогда** после возврата на Profile и pull-to-refresh галочка обновляется.

### US5 — Офлайн (P2)

**Когда** пользователь открывает Profile офлайн, **тогда** раздел показывает последние известные значения (из кэша), без индикатора ошибки; pull-to-refresh без сети — silent ignore.

### US6 — Приватность (P1)

**Когда** сервер возвращает отчёт, **тогда** данные содержат только булевы флаги для текущего пользователя; никаких timestamp отдельных событий, никакой аналитики.

### US7 — Backfill для существующих пользователей (P1)

**Когда** бэкенд разворачивает спеку, **тогда** backfill скрипт проходит по всем существующим пользователям и заполняет `user_feature_adoption` на основе:
- SQL-deriveable флагов (`created_recipe`, `connected_telegram`, `connected_mcp_assistant`, `sent_assistant_message`) — одним пакетом через `INSERT ... SELECT`.
- Yjs-derived флагов (`imported_recipe`, `created_collection`, `shared_recipe`, `used_shopping_list`) — итеративно через `yjsService` по каждому пользователю (медленно, но разово).
- `installed_native_app` и `installed_watch_app` — **не backfill'ятся** (client-only; флаги появляются при первом входе в нативку / первом открытии watch app с сессией).
- `named_with_emoji` — backfill'ится по текущим названиям в recipe/collection Yjs-документах; историю удалённых названий не восстанавливаем.

## Требования

### Native

#### FR-038-N1 — Размещение в Profile

Строка-ссылка в `AccountView` внутри секции аккаунта (под seed phrase, над публичными профилями), ведёт в `FeatureAdoptionDetailView` со списком `FeatureAdoptionRow`, генерируемых из `FeatureAdoptionItem` enum (CaseIterable, 11 кейсов). На экране детализации — только navigation title, без дублирующего заголовка секции и без footer-счётчика.

#### FR-038-N2 — Cache

Локальный кэш в `UserDefaults` по ключу `feature-adoption-cache` (JSON-словарь `feature → bool`). Загружается синхронно при отрисовке раздела (без индикатора загрузки), обновляется асинхронно из сети. Срок кэша — без TTL, считается валидным до следующего успешного запроса.

#### FR-038-N3 — Refresh

- При появлении раздела (`.task`) — фоновый запрос `AccountAPI.fetchFeatureAdoption()`, обновление кэша и UI.
- Pull-to-refresh в `AccountView` — повторный запрос.
- При ошибке/офлайне — silent, остаётся кэш.

#### FR-038-N4 — `installed_native_app` trigger

В `AuthService`:

- `registerAuto()` — после успешного вызова и сохранения userId в `SharedAuthStore`, вызвать `markFeatureInstalled()` (см. ниже).
- `loginWithSeed(_:)` — то же самое после успешного логина.
- `restoreAuthenticationState()` — **не триггерит** запрос (это восстановление сессии на том же устройстве, а не «первый вход в нативку»).

`markFeatureInstalled()`:

1. Проверить локальный флаг `UserDefaults.standard.bool(forKey: "feature-adoption.installed-reported")`. Если уже true — выйти (идемпотентность per-account: флаг стирается в `clearForLogout()` при logout/wipe/account-deletion, чтобы новый аккаунт на этом устройстве снова отправил POST — см. changelog 2026-08-03).
2. Записать в кэш `feature-adoption-cache["installed_native_app"] = true` (instant UI update).
3. Fire-and-forget `AccountAPI.markFeatureAdoption("installed_native_app")`. Не блокировать UI.
4. При успехе — выставить `feature-adoption.installed-reported = true`.
5. При ошибке — оставить флаг не выставленным; повторить при следующем запуске (cold start) через `AppContainer.task`. Достаточно одной попытки за запуск. Все ветки (skip/begin/ok/failed) логируются через `AppLog` для диагностики.

#### FR-038-N5 — i18n

Все 11 заголовков + onboarding footnote — в `Localizable.xcstrings` (RU/EN). Префикс ключей: `account.feature-adoption.item.*` (заголовки) и `account.feature-adoption.item.*.footnote` (подписи). Плюс заголовок раздела `account.feature-adoption.title`. Без хардкода в SwiftUI.

#### FR-038-N6 — `installed_watch_app` trigger (watchOS)

В `WatchFeatureAdoptionReporter` (watch target):

- Первое открытие watch app с `WatchCredentialsStore.userId != nil` — fire-and-forget `FeatureAdoptionAPI.markFeatureAdoption("installed_watch_app")`.
- Идемпотентность на устройстве: `UserDefaults` ключ `feature-adoption.watch-app-opened-reported.<userId>` (per-user, не глобальный).
- `userId` захватывается до `Task`; POST и запись флага только если сессия не сменилась.
- При purge creds с iPhone (`userId: null` в WCSession) — локальный reported-флаг для предыдущего `userId` сбрасывается.
- POST делегируется в `RecipeScalerCore.FeatureAdoptionAPI` (общий с iPhone `AccountAPI.markFeatureAdoption`).
- При ошибке сети — флаг не выставляется; повтор при следующем открытии с сессией.

### Server

#### FR-038-S1 — Новая таблица

```sql
CREATE TABLE IF NOT EXISTS user_feature_adoption (
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  feature    TEXT NOT NULL CHECK (feature ~ '^[a-z_]+$'),
  first_used TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, feature)
);

CREATE INDEX IF NOT EXISTS idx_user_feature_adoption_user
  ON user_feature_adoption(user_id);
```

Миграция — в `recipe-scaler-web/server/migrations/` в двух вариантах: `2026_06_25_user_feature_adoption_public.sql` и `_dev.sql`, по существующей конвенции (см. `2026_06_13_add_timers_recipe_id_*.sql`).

#### FR-038-S2 — Endpoint отчёта

`GET /api/users/me/feature-adoption` (auth: `requireUserId`).

**Response 200:**
```json
{
  "success": true,
  "data": {
    "installed_native_app": false,
    "imported_recipe": true,
    "created_recipe": true,
    "created_collection": false,
    "shared_recipe": false,
    "connected_telegram": true,
    "connected_mcp_assistant": false,
    "sent_assistant_message": false
  }
}
```

Все 11 ключей присутствуют всегда. Логика — один `SELECT feature FROM user_feature_adoption WHERE user_id=$1`, маппинг в 11 булей. Никаких JOIN, никаких read-pass на лету.

**Headers**: `Cache-Control: private, max-age=60`.

#### FR-038-S3 — Endpoint записи (generic)

`POST /api/users/me/feature-adoption` (auth: `requireUserId`).

**Body:**
```json
{ "feature": "<feature_key>" }
```

Schema (zod): `{ feature: z.enum([...FEATURE_KEYS]) }`.

Сервер делает `INSERT ... ON CONFLICT (user_id, feature) DO NOTHING`. Idempotent — повторные запросы с тем же feature не создают новую запись и не обновляют `first_used`.

**Rate limit**: стандартный `rateLimiter` bucket. Используется native клиентом для `installed_native_app`; другие client-reported флаги в v1 не планируются, но endpoint generic.

#### FR-038-S4 — Live events (server-side)

При каждом действии, соответствующем флагу, серверный код вызывает helper `featureAdoptionService.mark(userId, feature)` — тонкая обёртка над `INSERT ... ON CONFLICT DO NOTHING`. Точки вызова:

| Feature | Точка вызова в коде | Файл |
|---------|---------------------|------|
| `imported_recipe` | Успешный импорт (после создания recipe doc) | `recipe-service.ts` в `createRecipeFromUrl`/`createRecipeFromText` |
| `created_recipe` | Создание recipe row в БД | `recipe-service.ts` в `createRecipeInDatabase` |
| `created_collection` | Listener на collection doc: первое появление непустой `folders` записи | `yjs-service.ts` (новый observeDeep на `folders` Y.Array) |
| `shared_recipe` | Listener на recipe doc: первое `isPublic=true` | `yjs-service.ts` (новый observe на recipe map field) |
| `connected_telegram` | После `INSERT` в `telegram_connections` | `telegram-service.ts` в `connectUser` |
| `connected_mcp_assistant` | После `INSERT` в `oauth_access_tokens` | `mcp-auth-service.ts` в `issueTokens` / `exchangeCodeForToken` |
| `sent_assistant_message` | После сохранения user-сообщения | `assistant-service.ts` в `respond`/`respondStream` |

Все вызовы — fire-and-forget (ошибка записи не валирует бизнес-операцию). Логировать warning при ошибке.

#### FR-038-S5 — Yjs listeners для `created_collection` и `shared_recipe`

Эти флаги нельзя посчитать из SQL. Варианты:

- **A (реализуем в v1):** Yjs observe listener в `yjs-service.ts`. Когда collection doc загружается в память сервером (при `load_document`), подписываемся на `folders` Y.Array. При первом `length > 0` вызываем `mark(userId, 'created_collection')`. Аналогично для recipe doc: подписываемся на `recipe` Y.Map, при первом `isPublic === true` — `mark(userId, 'shared_recipe')`.
- **B (fallback для документов, которые не загружались после деплоя):** backfill скрипт (FR-038-S6) покрывает существующие данные.

Listener idempotent — подписка снимается после первого триггера (флаг уже true, повторных событий не будет).

**Риск:** если документ ни разу не загружался после деплоя, флаг не сработает через live event. Mitigation: периодический (раз в неделю) incremental backfill скрипт, который проверяет флаги для активных пользователей.

#### FR-038-S6 — Backfill скрипт

`recipe-scaler-web/server/scripts/backfill-feature-adoption.ts`. Запуск: `NODE_ENV=production bun server/scripts/backfill-feature-adoption.ts --env .env.prod [--apply]` (без `--apply` — dry run).

**Phase 1 — SQL-deriveable (быстро, один пакет):**

```sql
INSERT INTO user_feature_adoption (user_id, feature)
SELECT DISTINCT user_id, 'created_recipe' FROM recipes
ON CONFLICT DO NOTHING;

INSERT INTO user_feature_adoption (user_id, feature)
SELECT DISTINCT user_id, 'connected_telegram' FROM telegram_connections
ON CONFLICT DO NOTHING;

INSERT INTO user_feature_adoption (user_id, feature)
SELECT DISTINCT user_id, 'connected_mcp_assistant' FROM oauth_access_tokens
ON CONFLICT DO NOTHING;

INSERT INTO user_feature_adoption (user_id, feature)
SELECT DISTINCT user_id, 'sent_assistant_message' FROM assistant_messages
WHERE role = 'user'
ON CONFLICT DO NOTHING;
```

**Phase 2 — Yjs-derived (медленно, по каждому пользователю):**

```typescript
for (const user of allUserIds) {
  // Collection doc — check folders
  const collectionState = await supabase.from('recipe_collections').select('yjs_state').eq('user_id', user).single();
  if (collectionState.data?.yjs_state) {
    const doc = new Y.Doc();
    Y.applyUpdate(doc, collectionState.data.yjs_state);
    const folders = doc.getArray('folders');
    if (folders.length > 0) {
      await mark(user, 'created_collection');
    }
  }

  // Recipe docs — check originalRecipeLink (imported) и isPublic (shared)
  const recipes = await supabase.from('recipes').select('yjs_state').eq('user_id', user);
  let imported = false, shared = false;
  for (const r of recipes.data ?? []) {
    const doc = new Y.Doc();
    Y.applyUpdate(doc, r.yjs_state);
    const recipe = doc.getMap('recipe');
    if (recipe.get('originalRecipeLink')) imported = true;
    if (recipe.get('isPublic') === true) shared = true;
    if (imported && shared) break;
  }
  if (imported) await mark(user, 'imported_recipe');
  if (shared) await mark(user, 'shared_recipe');
}
```

Логирует прогресс каждые 100 пользователей. Параметр `--limit N` для теста на первых N юзерах. Параметр `--only-sql` — пропустить Phase 2 (быстрый smoke).

`installed_native_app` — **не backfill'ится**.

### Контракты

См. [`contracts/feature-adoption-api.md`](contracts/feature-adoption-api.md).

## Вне scope

- **Веб-UI**: раздел только в native iOS приложении. Backend готов обслуживать любые клиенты, но в `recipe-scaler-web` UI не добавляется.
- Аналитика событий (количество, временные ряды) — только булевы флаги.
- Расширение списка за пределы 11 пунктов — следующая итерация.
- Push-уведомления о новых доступных действиях.
- Gamification (уровни, награды, проценты).
- Client-side optimistic update после локального действия (например, после импорта рецепта в этой же сессии галочка становится активной без pull-to-refresh) — следующий spec, если UX потребует. Сейчас единственный optimistic update — `installed_native_app` (FR-038-N4).
- Live update через Socket.IO (событие `feature_adoption_updated`) — overkill для v1.
- UI для скрытия/сворачивания раздела — пользователь всегда видит 11 пунктов.

## Критерии успеха

- **SC-001**: Раздел виден вверху Profile сразу при открытии вкладки (из кэша), без индикатора загрузки.
- **SC-002**: Пользователь делает `registerAuto` или `loginWithSeed` в нативке → после этого `GET /feature-adoption` возвращает `installed_native_app: true`.
- **SC-003**: На свежем аккаунте после первого импорта рецепта и pull-to-refresh `imported_recipe` и `created_recipe` становятся выполненными.
- **SC-004**: После отправки первого сообщения ассистенту и pull-to-refresh `sent_assistant_message` выполнена.
- **SC-005**: После backfill скрипта (запуск в prod) ≥95% активных пользователей имеют корректно проставленные SQL-deriveable флаги (`created_recipe`, `connected_telegram`, `connected_mcp_assistant`, `sent_assistant_message`).
- **SC-006**: Офлайн: раздел показывается из кэша, нет ошибки, нет индикатора.
- **SC-007**: Серверный endpoint возвращает ровно 11 ключей, без раскрытия userId, timestamps или других приватных данных.
- **SC-008**: `POST /feature-adoption` idempotent — 5 последовательных запросов с тем же feature не создают 5 записей.
- **SC-009**: Все 11 заголовков локализованы (RU/EN), нет хардкода в SwiftUI.
- **SC-010**: После включения share у рецепта через веб-клиент и загрузки этого doc сервером (например, при следующем sync) → live listener проставляет `shared_recipe=true` без запуска backfill.
- **SC-011**: После успешного сохранения рецепта или активной коллекции с ведущим эмодзи `named_with_emoji=true`; удалённые папки и названия без ведущего эмодзи флаг не создают.

## Артефакты

- [`plan.md`](plan.md)
- [`contracts/feature-adoption-api.md`](contracts/feature-adoption-api.md)
- `quickstart.md` (опционально)

## Связанные спеки

| Спека | Связь |
|-------|-------|
| `013-account-settings` | Размещение раздела в `AccountView`, точки входа в `AuthService` |
| `010-recipe-import` | Триггер `imported_recipe` (server-side event) |
| `008-collection-mutations` / `026-recipe-collections` | Триггер `created_collection` (Yjs listener) |
| `012-sharing` | Триггер `shared_recipe` (Yjs listener) |
| `015-assistant` / `021-assistant-full` | Триггер `sent_assistant_message` (server-side event) |
| `020-account-telegram-export` | Триггер `connected_telegram` (server-side event) |
| MCP OAuth (`llm/API.md` § MCP) | Триггер `connected_mcp_assistant` (server-side event) |

## Changelog

### 2026-08-03 — `installed_native_app` per-account reset

- **Баг:** глобальный на устройство идемпотент-флаг `feature-adoption.installed-reported` не сбрасывался при logout/wipe. Первый аккаунт на устройстве выставлял флаг один раз, и для всех последующих аккаунтов `markFeatureInstalled` делал ранний `return` — POST `installed_native_app` для них не уходил, серверная галочка в веб-профиле не появлялась. На одном DEBUG-телефоне за 3 дня наблюдалось 7 разных userId — все кроме первого страдали этой проблемой.
- **Фикс:** `FeatureAdoptionStore.clearForLogout()` теперь стирает и `feature-adoption.installed-reported` (а не только cache + report). FR-038-N4 п.1 уточнён: идемпотентность — per-account, не per-device.
- **Логирование:** во все пути feature adoption добавлен `AppLog` — `feature_adoption_installed_begin/_ok/_failed/_skip`, `feature_adoption_post_begin/_ok/_failed`, `feature_adoption_fetched`, `feature_adoption_refresh_failed`, `feature_adoption_cleared`. Раньше пути были полностью silent, что и мешало диагностировать баг по debug-логу.

### 2026-06-29 — `installed_watch_app`

- 10-й пункт: watchOS client-reported флаг при первом открытии с сессией.
- `FeatureAdoptionAPI` в `RecipeScalerCore`; `WatchFeatureAdoptionReporter` с per-user UserDefaults.

### 2026-06-25 — refactored after DB audit

- Убрано «веб UI» — теперь только native iOS. Backend остаётся разделяемым.
- `installed_native_app` триггер изменён: не «первый запуск», а «успешная авторизация» (register-auto или login-with-seed). Не повторяется на том же устройстве.
- Заменён «гибридный read-pass» на **single-table-source-of-truth**: после аудита `migrations.sql` выяснилось, что `source_url`/`is_public`/`folders` живут только в Yjs doc, SQL их не достаёт.
- Добавлен backfill скрипт (FR-038-S6) как первоклассный артефакт.
- Добавлены Yjs listeners для `created_collection` и `shared_recipe` (FR-038-S5).
- Live events описаны для всех флагов, кроме `installed_native_app` (FR-038-S4).
