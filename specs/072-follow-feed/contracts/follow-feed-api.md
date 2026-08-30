# Contract: Follow / Feed API (spec 072)

**Спека**: [spec.md](../spec.md)
**Канон wire-контракта**: [`recipe-scaler-web/specs/072-follow-feed/spec.md` § Wire-контракт, § Гашение точки](../../../../recipe-scaler-web/specs/072-follow-feed/spec.md)

Маршруты follow (`POST`/`DELETE`/`PATCH /api/v1/users/:username/follow`, `GET /api/v1/users/me/following/:username`), лента (`GET /api/v1/feed`, `GET /api/v1/feed/badge`, `POST /api/v1/feed/seen`), поле `followers_count` в `GET /api/users/public/:username` и dot-key ошибок (`follow.*`) — см. канон. Native-реализация: `FollowAPI.swift` / `FeedAPI.swift`; даты декодируются как `String` (ISO 8601 с дробными секундами не проходит `.iso8601`-декодер).

**Push payload (072, 2026-08-30):** APNs-`data` несёт `url` (deep link): единичная публикация — `/public/@/{username}/{recipeId}` → `.openPublicRecipe`; дайджем — `/discover/feed` → `.openDiscoverFeed` (сегмент «Моя лента»). Сервер шлёт web-hash-форму (`https://recipe-scaler.ru/#/…`) — `DeepLinkRouter.handlePushURL` нормализует fragment в path до парсинга. `url` приоритетнее legacy-поля `recipeId` (fallback только при отсутствии/нераспарсенном `url`).
