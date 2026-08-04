# Контракт: Timer payload с stepId

**Spec**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md)

> Общий контракт с web/server для поля `stepId` в payload таймера. Spec 056 вводит
> это поле в native, server/web должны переваривать его без поломок.

## Поле

```json
{
  "id": "timer-1722634200000",
  "name": "Таймер для шага 3",
  "duration": 600,
  "startedAt": 1722634200000,
  "isPaused": false,
  "lastUpdated": 1722634200000,
  "recipeId": "uuid-of-recipe",
  "endTime": 1722634800000,
  "stepId": "step-uuid-or-number-string"
}
```

### `stepId`

- **Type**: `string | null` (опциональное, backward-compatible)
- **Семантика**: идентификатор шага рецепта, к которому привязан таймер. На iOS это UUID блока `RecipeDescriptionBlock.orderedStep(id:number:runs:)`, приведённый к строке.
- **Source of truth**: клиент создаёт таймер из контекста шага → передаёт `stepId`. Сервер хранит и фанит обратно через WebSocket fan-out.
- **Backward compat**: payload без `stepId` валиден и означает «таймер не привязан к шагу». Web и старые нативные клиенты продолжают работать.

## Сервер

- Сервер использует permissive JSON (не валидирует схему строго). Поле `stepId` добавляется как pass-through.
- WebSocket fan-out: при `timerCreated` / `timerStarted` / `timerPaused` / `timerResumed` / `timerDeleted` events — `stepId` присутствует в payload если был создан с ним.
- База данных: если хранится в БД — добавить колонку `stepId TEXT NULL` или положить в jsonb поле без schema migration.

## Web (`recipe-scaler-web`)

- Web клиент должен принимать payload с `stepId` без ошибки. Десериализация — опциональное поле.
- Web UI в v1 не показывает step badge у таймера. Это может быть v1.1 web parity если будет востребовано.
- Если web создаёт таймер — `stepId` опционально может быть передан из контекста шага.

## Cross-platform совместимость

| Платформа | Создаёт с stepId | Читает stepId | Показывает в UI |
|-----------|------------------|---------------|-----------------|
| iOS native (spec 056) | да (из CookingModeView) | да | да (в CookingModeView) |
| Web | нет в v1 | да (без ошибок) | нет в v1 |
| watchOS app (spec 039) | нет | да (без ошибок) | нет |
| Widget / Live Activity | n/a | да (без ошибок) | нет |

## End-to-end проверка перед релизом

1. Создать таймер с `stepId` на iOS native → проверить payload в server logs.
2. Открыть web клиент → таймер виден, нет ошибок в консоли, payload с `stepId` корректно десериализован.
3. Открыть watch app → таймер виден, работает pause/resume.
4. Удалить таймер на web → на iOS нативно корректно обработано через WebSocket fan-out.
5. Создать таймер **без** `stepId` на web → iOS нативно корректно показывает таймер, `stepId == nil`.

## Тесты (native)

- `TimerSyncServiceTests.test_stepId_includedInPayload` — serialization includes stepId.
- `TimerSyncServiceTests.test_legacyPayload_stepId_nil` — old payload without stepId deserializes fine.
- `TimerSyncServiceTests.test_stepId_roundTrip` — create → serialize → deserialize preserves stepId.
