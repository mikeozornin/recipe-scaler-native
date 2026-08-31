# План: Подписки на авторов и лента новых рецептов (native)

**Дата**: 2026-08-25
**Спека**: [spec.md](./spec.md)

## Границы

- **В scope**: `FollowAPI`/`FeedAPI`, сторы (`FollowStore`, `FeedStore`, `FeedBadgeStore`), UI (кнопка/дропдаун подписки на профиле, сегмент+лента в Discover, точка на табе/сегменте), push-роутинг, i18n, E2E `FeedPage`.
- **Вне scope**: сервер и web-клиент (web plan); офлайн-кэш ленты на диск; виджеты/Watch/App Intents.
- **STOP conditions**: серверный контракт 072 не в проде/стейджинге (UI упрётся в 404); сборка красная после `xcodebuild build`.

## Конституционная проверка

| Gate | Статус | Evidence / обоснование |
|------|--------|------------------------|
| CRDT-first | N/A | REST-only фича, как 011/012; Y.Doc не затрагивается |
| Web parity | PASS | parity-чеклист в спеке; один контракт `shared/rest-api.md` |
| Offline-first | PASS (осознанное отступление) | Лента REST-only in-memory (FR-DISC-001 паттерн 011); задокументировано в Non-goals спеки |
| Native UI | PASS | SwiftUI + `.appBody()`; переиспользуются карточки Discover |
| Phased delivery | PASS | API → сторы → UI → E2E; сервер впереди |
| i18n | PASS | Ключи `discover.follow.*`/`discover.feed.*` в `Localizable.xcstrings` en+ru |
| Documentation | PASS | `contracts/follow-feed-api.md` — thin pointer |

## Очерёдность

1. **`FollowAPI` + `FollowStore`** — минимальный вертикальный срез: кнопка на профиле работает.
2. **`FeedAPI` + `FeedStore`** — лента с keyset-догрузкой.
3. **`FeedBadgeStore` + точка** — таб Discover/сегмент; оптимистичное гашение после успешной страницы-1 (`seen`-эхо из `FeedStore`).
4. **UI-полировка**: пустые состояния (нет подписок / нет нового), счётчик подписчиков, чип «Новое», гостевой login-flow.
5. **Push-роутинг** — тап по APNs-пушу через `DeepLinkRouter` (059): единичный — публичный рецепт; дайджем — сегмент «Моя лента» (`/discover/feed`; решение 2026-08-30).
6. **E2E + lint-i18n** — `FeedPage` page object, US1–US4, US14.

## Изменения

| Файл | Действие | Почему |
|------|----------|--------|
| `RecipeScalerNative/Services/FollowAPI.swift` | Создать | follow/unfollow/bell/status; паттерн `SystemBannerAPI` (061) |
| `RecipeScalerNative/Services/FeedAPI.swift` | Создать | feed (keyset, `isNew`, `snapshotAt`)/badge/seen (эхо `seen_at`) |
| `RecipeScalerNative/Stores/FollowStore.swift` | Создать | `@MainActor @Observable`; `following`/`pushOptIn` для текущего профиля |
| `RecipeScalerNative/Stores/FeedStore.swift` | Создать | Страницы ленты + курсор + pull-to-refresh + авто-догрузка (100/стр, inline «Повторить») + эхо `seen { seen_at: snapshotAt }` после успешной страницы-1 |
| `RecipeScalerNative/Stores/FeedBadgeStore.swift` | Создать | `hasNew` + оптимистичное локальное гашение (маркер двигает `FeedStore`) |
| `RecipeScalerNative/Views/DiscoverRootView` (сущ.) | Изменить | Сегмент «Подборки \| Моя лента» (ephemeral, без персистенции), лента, чип «Новое», пустые состояния |
| `RecipeScalerNative/Views/DiscoverPublicProfileView` (сущ.) | Изменить | Кнопка «Подписаться» → дропдаун «Подписка» (Отписаться / Подписка / Подписка и уведомления), счётчик подписчиков, a11y ids |
| `RecipeScalerNative/Views/AppShellView.swift` | Изменить | Красная точка на табе Discover |
| `RecipeScalerNative/App/AppContainer.swift` | Изменить | DI трёх сторов; `bootstrap(userId:)` → `feedBadgeStore.refresh()` |
| `RecipeScalerNative/Resources/Localizable.xcstrings` | Изменить | Ключи en+ru по канону web spec 072 § UX |
| `RecipeScalerNativeTests/…` + page object `FeedPage` | Создать | US1–US4, US14 E2E; unit: оптимистичное гашение, сбой страницы-1 маркер не двигает |
| `specs/072-follow-feed/contracts/follow-feed-api.md` | Создать | Thin pointer на web spec 072 § Wire-контракт |

## Downstream consumers

- **SwiftUI views**: `DiscoverRootView`, `DiscoverPublicProfileView`, `AppShellView` — подписка на сторы.
- **Cross-process**: widgets/watch/Live Activity/App Intents не затрагиваются (Non-goals).
- **Sync boundaries**: Yjs не трогаем; серверный контракт = `shared/rest-api.md`.
- **Persisted state**: нет — сегмент «Подборки \| Моя лента» ephemeral (вход в Discover всегда «Подборки», паритет с веб-URL-навигацией); маркер просмотра — серверный.
- **Tests / verify scripts**: E2E `FeedPage`; `lint-i18n.sh`.

## Positive invariants

| Observable effect | Положительный инвариант | Test/verifier ID |
|---|---|---|
| Тап «Подписаться» | `FollowStore.following == true` после `follow()`; кнопка → дропдаун «Подписка» | `FeedPage.test_follow_button` (E2E US1) |
| Колокольчик ON → автор публикует | APNs-push получен; тап открывает публичный рецепт (дайджем — корень Discover) | E2E-мок push + `DeepLinkRouter` тест |
| Успешная загрузка страницы-1 ленты | `POST /api/v1/feed/seen { seen_at: snapshotAt }` отправлен (`FeedStore`); точка гаснет (оптимистично в `FeedBadgeStore`); повторный `badge` → `hasNew: false` | `FeedStoreTests.test_first_page_marks_seen` |
| Сбой загрузки страницы-1 | `POST /seen` не отправлен; маркер не двигается; точка возвращается при следующем `badge` | `FeedStoreTests.test_failed_first_page_does_not_mark_seen` |
| Лента | Догрузка курсором не даёт дублей карточек; `isNew`-карточки несут чип «Новое» | `FeedStoreTests.test_pagination_no_dupes` |
| Логаут | Все три стора сброшены (`clearForLogout`) | `FollowFeedStoresTests.test_logout_reset` |

## Async lifecycle

| Операция | Captured identity | Re-check после await | Cancellation owner | Stale completion test |
|---|---|---|---|---|
| `FollowStore.refresh(username)` | username + session | сравнить запрошенный username с активным профилем | `Task` view lifecycle | `FollowStoreTests.test_stale_refresh_ignored` |
| `FeedStore.loadFirstPage()` → `POST /seen` + локальное гашение точки | session epoch | успех загрузки + `snapshotAt` до отправки `POST /seen`; сравнить epoch с активной сессией | `FeedStore` own `Task` | `FeedStoreTests.test_first_page_after_logout_discarded` (сброс сессии → `POST /seen` не отправлен) |
| `FeedStore.loadPage(cursor)` | session epoch | single-flight guard на курсор | `FeedStore` own `Task` | `FeedStoreTests.test_cancelled_page_discarded` |
| `FeedBadgeStore.refresh()` (badge) | session epoch | badge state re-read после await | `FeedBadgeStore` | `FeedBadgeStoreTests.test_stale_badge_discarded` |

## Teardown / resource inventory

| Entry path | In-memory | Tasks/streams | Persisted state | Cross-process / OS surface | Positive postcondition |
|---|---|---|---|---|---|
| logout | сторы очищены | все refresh-таски отменены | серверный маркер не тронут | нет | Новый пользователь видит пустые сторы |
| account switch | то же, что logout | то же | то же | нет | Нет мелькания чужих данных |
| cold start | пустые сторы до bootstrap | bootstrap запускает badge-refresh | нет | нет | Точка появляется только после badge-ответа |
| network fail | последний in-memory экран | задача завершена ошибкой | нет | нет | Silent (US6): UI не меняется; `POST /seen` не отправлен — маркер не двигается |

## Locale / theme consumers

- SwiftUI environment: `.appBody()`/`.appFootnote()` на всех новых текстах; Martian.
- Push-тексты: серверные (`locale` поле push payload, 023 FR-PUSH-005) — клиент только роутит.
- Cached assets: аватары/превью — существующий URLCache (011).

## Compatibility / migration

- Current contract: web spec 072 § Wire-контракт (`follow.*`, `feed` с `isNew`/`snapshotAt`, `badge`, `seen` с эхом `seen_at`).
- Unknown future fields: DTO-декодинг `ExtraUnknownAndDecodingError`-политикой проекта (см. конституцию) — неизвестные поля игнорируются, отсутствующие опциональные — дефолты.
- Server error dot-keys (`follow.*`) добавляются в `ServerErrorCode` enum + локализацию тем же change (US9 native).

## Unknown IDs and fallback policy

- DEBUG/CI: unknown `username` → ошибка `follow.user-not-found` показывается; hard failure только для контракта (DTO-мисматч).
- Release: safe user-facing state + structured log (AppLog).
- Deep link на удалённый рецепт: существующий fallback публичных страниц (404 → «рецепт недоступен»).

## Human gates

- [ ] План просмотрен пользователем.
- [ ] Review-agent после имплементации (review-isolation).
- [ ] layout.md не требуется (не Figma-driven; переиспользуются существующие компоненты).

## Verification

- `xcodebuild -project … build` — BUILD SUCCEEDED (fix-until-green, docs/AGENT-WORKFLOW.md).
- `xcodebuild … test -only-testing:RecipeScalerNativeTests` — зелёный.
- `bash scripts/lint-i18n.sh` — exit 0.
- E2E `FeedPage` (US1–US4, US14) против REST-фикстур.
- UI-верификация: simulator screenshot (vision models) или accessibility server.

## Rollback / maintenance

- Фича не behind feature-flag (сервер additive; UI не показывается без данных: нет подписок → пустые состояния).
- Откат: revert UI-коммитов; серверные таблицы additive — можно оставить.
- Временных allowlist нет.
