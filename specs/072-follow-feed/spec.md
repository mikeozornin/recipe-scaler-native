# Спецификация: Подписки на авторов и лента новых рецептов (native)

**Ветка**: `072-follow-feed`
**Дата**: 2026-08-25
**Статус**: Draft
**Canonical API spec**: [`../recipe-scaler-web/specs/072-follow-feed/spec.md`](../../../recipe-scaler-web/specs/072-follow-feed/spec.md) — схема (`user_follows`, `recipes.published_at`), wire-контракт (follow-маршруты, `GET /api/v1/feed`, `GET /api/v1/feed/badge`), предикат видимости, антиабьюз. Здесь — native UI, клиент, сторы и i18n.
**Зависимости**: `011-discover-public` (`DiscoverRootView`, `DiscoverPublicProfileView`, `DiscoverAPI`, карточка публичного рецепта), `017-discover-enablement` (вкладка активна), `007-app-shell-navigation` (таб Discover, reset tab), `023-push-notifications` (APNs-подписки), `059-universal-links` (роутинг пуша → публичный рецепт), `013-account-settings` / auth (`requireUserId`, login-flow для гостя), `AppContainer` (DI, паттерн `SystemBannerStore` из `061-system-banner`)
**Эталоны**: `SystemBannerStore` + `bootstrap(userId:)` refresh (061), `@AppStorage` per-device префы, `requestJSON` snake_case-декодинг

## Контекст и мотивация

Серверная фича 072 (подписки + pull-based лента + opt-in пуши) проектируется одновременно с web-клиентом. Native уже умеет публичные профили (`DiscoverPublicProfileView`) и Discover-вкладку — подписка встраивается туда без новых навигационных сущностей. Требование — **синхронный релиз**: сервер + web + native стартуют на одном контракте, без периода «фича есть на вебе, в приложении нет».

## Цель

1. Кнопка «Подписаться»/«Вы подписаны» + колокольчик (push opt-in) на чужом публичном профиле.
2. Сегмент «Подборки | Мои подписки» в Discover; лента новых публичных рецептов авторов.
3. Красная точка на табе Discover и сегменте при новом контенте; гасится открытием ленты.
4. APNs-push о новом рецепте у opt-in-автора; тап ведёт на публичный экран рецепта.

## Non-goals

- Реакции/комментарии, публичные списки подписок (нет и на сервере).
- Алгоритмическая лента, ранжирование.
- Offline-кэш ленты на диск (только in-memory + silent refresh — **осознанное отступление** от FR-DISC-001 из 011, где офлайн показывает последний кэш с сообщением; для ленты вместо сообщения — тихий отказ обновления, см. US6).
- Виджет/Watch/Live Activity/App Intents для подписок.
- Web-часть (канон в web spec 072).

---

## Границы (Scope)

**Входит:**

- `FollowAPI`: follow/unfollow/PATCH bell/status; `FeedAPI`: feed (keyset), badge, seen. `APIClient.requestJSON`, snake_case, `.iso8601`.
- `FollowStore` — статус связи для текущего просматриваемого профиля (`following`, `pushOptIn`).
- `FeedStore` — страница ленты + курсорная догрузка + pull-to-refresh; `FeedBadgeStore` — `hasNew` для точки.
- Сегмент-контрол в `DiscoverRootView` («Подборки | Мои подписки»), выбор в `@AppStorage("discover-feed-segment")` (per-device, как web `localStorage`).
- Маркер просмотра — **на сервере** (`feed_state.last_seen_at`, per-user): `POST /api/v1/feed/seen` при открытии ленты, `GET /api/v1/feed/badge` для точки. Сервер создаёт запись при первом `POST /follow` — публикации после первой подписки зажигают точку, до — нет. Синхронизация между устройствами из коробки; локального маркера в `UserDefaults` нет.
- Красная точка: overlay на иконке таба Discover в `AppShellView` + на сегменте «Мои подписки».
- Кнопка Follow + колокольчик в `DiscoverPublicProfileView` (не на своём профиле); гостю — существующий login-flow.
- Счётчик подписчиков (чип в шапке профиля, плюрализация en/ru).
- Push-роутинг: тап по пушу → публичный рецепт через существующий роутер (паттерн 059).
- i18n `discover.follow.*` / `discover.feed.*` в `Localizable.xcstrings` (en+ru), a11y identifiers, page objects.

**Не входит:** см. Non-goals.

## Архитектура

- **DTO**: `FeedEntryDTO` (`recipeId`, `username`, `displayName`, `avatarRef`, `imageRef`, `name`, `publishedAt`), `FeedBadgeDTO` (`hasNew`), `FollowStatusDTO` (`following`, `pushOptIn`), `followersCount` в существующем public-profile DTO (`GET /api/users/public/:username`, web spec 072 § Wire-контракт).
- **Networking**: `enum FollowAPI` / `enum FeedAPI`, статические методы на `APIClient` — паттерн `SystemBannerAPI` (061). Destructive-подтверждений нет: unfollow не деструктивен (ничего не удаляет у автора).
- **Сторы**: `@MainActor @Observable`, живут в `AppContainer` (`followStore`, `feedStore`, `feedBadgeStore`). `feedBadgeStore.refresh()` — один раз в `bootstrap(userId:)` после `SystemBannerStore` (без polling); повторный вызов — на `onAppear` Discover.
- **Views**: сегмент = `Picker(.segmented)` в шапке `DiscoverRootView`; карточки ленты — переиспользовать карточку Discover-рецепта + строка автора (аватар, имя, время `publishedAt`).
- **Гашение точки**: `onAppear` сегмента «Мои подписки» → `feedBadgeStore.markSeen()` — оптимистично гасит локально + `POST /api/v1/feed/seen` (сервер пишет своё `now()`); сервер — источник правды, при ошибке сети точка вернётся после следующего `badge`-запроса.
- **Logout**: `clearForLogout()` у трёх сторов (сброс ленты, статуса, точки) — паттерн `SystemBannerStore.clearForLogout()` (061). Серверный маркер не трогается.
- **Async lifecycle**: задачи refresh — `Task`, отменяемые при disappear стора-владельца; без глобальных таймеров. Правила [docs/agents/ASYNC-LIFECYCLE.md](../../docs/agents/ASYNC-LIFECYCLE.md).

```mermaid
sequenceDiagram
    participant B as AppContainer.bootstrap(userId:)
    participant S as Server
    participant G as FeedBadgeStore
    participant F as FeedStore
    participant D as DiscoverRootView
    B->>G: refresh() → GET /api/v1/feed/badge
    G->>S: badge (мои followee, published_at > feed_state.last_seen_at, предикат видимости)
    G-->>D: hasNew → точка на табе/сегменте
    D->>F: сегмент «Мои подписки» onAppear
    F->>F: GET /api/v1/feed?cursor (in-memory cache)
    F->>G: markSeen() → POST /api/v1/feed/seen
    G->>S: feed_state.last_seen_at = now() (сервер)
    G-->>D: точка погашена (оптимистично)
```

## Синхронность с web (parity checklist)

| Контракт | Web | Native | Общий канон |
|---|---|---|---|
| Follow/unfollow/bell/status | ✅ | ✅ этот спека | web spec 072 § Wire-контракт |
| `GET /api/v1/feed` (keyset) | ✅ | ✅ | тот же |
| `GET /api/v1/feed/badge` | ✅ | ✅ | тот же |
| Красная точка (таб + сегмент, гашение открытием) | ✅ | ✅ | web spec 072 § Индикатор |
| Маркер просмотра | сервер `feed_state.last_seen_at` | тот же | синхронизация между устройствами; `POST /api/v1/feed/seen` + `badge` |
| Push текст/roутинг | VAPID | APNs | web spec 072 § Push |
| Пустые состояния, счётчик подписчиков | ✅ | ✅ | те же лок-ключи (значения en/ru синхронны) |

Релизный порядок: сервер (миграция 070 + эндпоинты) → web + native параллельно на одном API; расхождений контракта между клиентами нет — всё в `specs/shared/rest-api.md` в том же change, что и серверный код.

## Пользовательские сценарии

### US1 — Подписка (P0)

**Когда** залогиненный пользователь на чужом публичном профиле тапает «Подписаться», **тогда** `FollowAPI.follow` → кнопка «Вы подписаны», появляется колокольчик (выключен), счётчик автора +1.

### US2 — Колокольчик (P0)

**Когда** колокольчик включён и автор публикует рецепт, **тогда** приходит APNs-push (пайплайн 023); тап открывает публичный экран рецепта. Массовая публикация (≥2 рецептов одной мутацией) — один дайджем-пуш, тап ведёт в ленту. Выключен/нет подписки — пуша нет.

### US3 — Лента (P0)

**Когда** открыт сегмент «Мои подписки», **тогда** лента новых публичных рецептов (карточка: автор, фото, название, время); тап → публичный рецепт; pull-to-refresh; догрузка курсором без дублей.

### US4 — Точка нового (P1)

**Когда** `hasNew = true`, **тогда** красная точка на табе Discover и сегменте; открытие «Моих подписок» гасит обе до следующей публикации (`POST /api/v1/feed/seen`, серверный маркер — гашение видно и с других устройств). Нет записи `feed_state` (создаётся сервером при первом `POST /follow`) или нет подписок — точки нет. Повторный tap таба Discover с вложенного экрана → корень (FR-NAV-002), точка не гасится.

### US5 — Исчезновение контента (P0)

**Когда** автор скрыл рецепт/профиль или удалил аккаунт, **тогда** при следующем refresh элементы исчезают, ошибки в UI нет (silent).

### US6 — Офлайн (P1)

**Когда** сеть недоступна, **тогда** лента/точка тихо не обновляются (последний in-memory экран остаётся), follow-кнопка показывает локализованную ошибку, состояние не меняется.

### US9 — Серверные ошибки follow (P1)

**Когда** сервер отвечает ошибкой follow (`404 follow.user-not-found`, `409 follow.self-not-allowed`, `409 follow.too-many-follows`, `429 follow.rate-limited`, `404 follow.not-following` на PATCH колокольчика), **тогда** UI показывает человекочитаемое сообщение по dot-ключу (паттерн `ServerErrorCode` из 031, ключи добавляются в enum + `Localizable.xcstrings` en/ru тем же change), состояние кнопки не меняется.

### US7 — Гость (P1)

**Когда** гость тапает «Подписаться», **тогда** существующий login-flow; после входа — возврат на профиль, статус связи подтянут.

### US8 — Логаут (P0)

**Когда** пользователь разлогинивается, **тогда** сторы сброшены (`clearForLogout()`): лента, точка, follow-статус; чужие данные не мелькают при следующем входе.

## Верификация

- Build: `docs/AGENT-WORKFLOW.md` (fix-until-green).
- i18n: ключи en+ru в `Localizable.xcstrings`, `scripts/lint-i18n.sh` зелёный; Martian-типографика `.appBody()`.
- A11y identifiers: `discover-follow-button`, `discover-follow-bell`, `discover-feed-segment`, `discover-feed-list`, `discover-feed-card` (kebab-case, по правилам E2E).
- E2E (XCTest, page object `FeedPage`): US1–US4 против REST-фикстур (docs/E2E.md).
- UI-верификация через simulator accessibility server (не скриншоты).

## Артефакты

- `contracts/follow-feed-api.md` — thin pointer на web spec 072 § Wire-контракт (без дубления канона).
