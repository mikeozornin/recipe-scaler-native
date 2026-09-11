# Спецификация: Таблица процесса — native

**Номер**: 074  
**Дата**: 2026-09-12  
**Статус**: Draft (ждёт decode + cooking UI)  
**Канон (wire / server)**: [`recipe-scaler-web/specs/074-process-table/spec.md`](../../../recipe-scaler-web/specs/074-process-table/spec.md)  
**Схема JSON**: [`recipe-scaler-web/specs/074-process-table/contracts/process-table-v1.schema.json`](../../../recipe-scaler-web/specs/074-process-table/contracts/process-table-v1.schema.json)  
**Хеш**: порт [`recipe-scaler-web/shared/utils/process-table-source-hash.ts`](../../../recipe-scaler-web/shared/utils/process-table-source-hash.ts)

---

## Границы

**В scope:** чтение `Y.Map('recipe').processTable`, Do-No-Harm на запись recipe map, матрица готовки (merge consecutive, prep stack, scaled amounts), stale-баннер + `POST /api/recipes/:id/rebuild-process-table`, локальные чекбоксы, таймеры по `stepIndex`.

**Вне scope:** сервер (уже в web-репо); web cooking chrome (скрыт флагом); library-wide backfill (per-user ops — web `backfill-process-tables.ts`); редактор маппинга; голосовой wizard [056](../056-cooking-voice-mode/spec.md) как замена матрице (можно сосуществовать).

Web не показывает таблицу. Native — первый пользовательский клиент этого ключа.

---

## Контракт (кратко)

Канон — web spec § Native contract. Здесь только native-якоря.

| Что | Native |
|---|---|
| Decode | `JSON.parse` строки `processTable` → `version == 1`. Иначе как будто ключа нет |
| Preserve | `DocumentManager` / recipe writes MUST не дропать неизвестные ключи recipe map |
| Merge | Подряд идущие `assignments` в колонке → один span; текст — `cellTitles` первой строки span |
| Stale | Локальный SHA-256 канона (`id` + `originalAmount` + `unit` + plain steps) ≠ `sourceHash` → баннер, таблица остаётся |
| Rebuild | `POST /api/recipes/:id/rebuild-process-table` (Bearer, как `calculate-nutrition`). **Ждёт** LLM. 404/500 — тост |
| Checks | `UserDefaults` / in-memory, не Yjs |
| Timers | `timer-reference` в HTML шагов → первая cook-колонка с тем же `stepIndex` |

Импорт на сервере уже планирует `buildProcessTable` fire-and-forget. После sync ключ появится без отдельного REST read.

---

## User stories

### US1 — Ключ доезжает по sync

**Given** импорт на сервере записал `processTable`, **When** native открывает рецепт после sync, **Then** матрица декодируется. Битый JSON / не v1 — классический рецепт, ключ не удаляется.

### US2 — Save не стирает ключ

**Given** валидный `processTable`, **When** пользователь правит имя/ингредиенты/шаги, **Then** ключ остаётся в Y.Doc.

### US3 — Merge consecutive

**Given** assignments на строках 2–4 подряд в cook-колонке, **When** таблица нарисована, **Then** один span; строка 5 без assignment пустая.

### US4 — Stale + rebuild

**Given** хеш разъехался после правки шагов, **When** owner online жмёт пересчёт, **Then** `POST /api/recipes/:id/rebuild-process-table` и после успеха баннер гаснет.

---

## Code anchors (ожидаемые)

- `RecipeScalerNative/Services/YjsSync/DocumentManager.swift` — read string key, preserve on write
- `RecipeScalerCore/Networking/APIClient.swift` — rebuild path рядом с `calculate-nutrition`
- Новый parser/hash рядом с recipe Yjs readers
- Cooking UI — отдельный view; не ломать [056](../056-cooking-voice-mode/spec.md)

## Related

- Web canon: [`../../../recipe-scaler-web/specs/074-process-table/spec.md`](../../../recipe-scaler-web/specs/074-process-table/spec.md)
- Yjs mapping: [`../../docs/YJS-SCHEMA.md`](../../docs/YJS-SCHEMA.md)
