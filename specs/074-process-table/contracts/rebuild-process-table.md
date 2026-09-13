# Contract: POST /api/recipes/:id/rebuild-process-table

Канон: web spec 074 § Native contract / `server/src/routes/recipes.ts`.

| | |
|--|--|
| Method | `POST` |
| Path | `/api/recipes/:id/rebuild-process-table` |
| Auth | Bearer, как `POST /api/recipes/:id/calculate-nutrition` |
| Body | пустой |
| Success | `200 { "success": true }` — сервер **дождался** LLM + sanitize + Yjs patch |
| Forbidden / чужой | `404` |
| LLM / sanitize fail | `500` |

Native:

- Только owner + online. Discover/public не вызывает.
- Ждёт ответ (десятки секунд). Кнопка busy, single-flight.
- После 200: `YjsSyncService.refreshCurrentRecipe(recipeId)` (или эквивалент pull), затем баннер гаснет если хеш совпал.
- 404/500: локализованный тост; таблица и баннер на месте.
- Не вешать на import rate limiter — это server concern.

Captured identity: `recipeId`, `userId`, cooking/edit generation. После await не трогать UI, если identity сменилась.
