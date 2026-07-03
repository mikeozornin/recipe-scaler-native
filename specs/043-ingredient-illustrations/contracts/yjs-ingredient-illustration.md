# Контракт: Yjs — иллюстрация ингредиента

**Фича**: `043-ingredient-illustrations`  
**Статус**: draft  
**Эталон (веб)**: `recipe-scaler-web/shared/types/recipe-yjs.ts`, `recipe-scaler/src/utils/ingredient-illustration-picker-bindings.ts`

## Ключи в `Y.Map` ингредиента (v2/v3 `Y.Array('ingredients')`)

| Ключ | Тип wire | Обязательность | Семантика |
|------|----------|----------------|-----------|
| `illustrationId` | string | optional | Slug из каталога (`registry.entries[].id`). Декоративная привязка; **не** меняет `name`. |
| `illustrationPickerCleared` | bool | optional | `true` — пользователь явно сбросил иконку; lazy auto-match на вебе **не** заполняет строку снова. |

Остальные ключи ингредиента без изменений (`id`, `name`, `amount`, `originalAmount`, `unit`, `order`, `isSeparator`, nutrition, …).

## Чтение (iOS)

- Отсутствие ключа → `illustrationId == nil`, `illustrationPickerCleared == false`.
- Пустая строка `illustrationId` → трактовать как nil в UI.
- Неизвестные ключи → игнорировать (forward compatibility).

## Запись — выбор в picker

Эквивалент `applyIngredientIllustrationPickerSelection`:

1. `ingMap.set('illustrationId', slug)`
2. Удалить `illustrationPickerCleared` или установить `false` (parity: веб передаёт `null` в `updateIngredientField` → delete key)

## Запись — сброс в picker

Эквивалент `applyIngredientIllustrationPickerClear`:

1. Удалить `illustrationId` из map
2. `ingMap.set('illustrationPickerCleared', true)`

## Полный save строки (`writeIngredient`)

При обновлении имени/qty/nutrition через существующий `updateIngredient(IngredientData)`:

- Если `illustrationId != nil` → записать ключ
- Если `illustrationId == nil` и **не** picker-cleared-only update → не удалять ключ без явного intent (избежать затирания при stale model); partial API предпочтительнее для picker

**Рекомендация:** picker использует **partial field update**, не полный `writeIngredient` из устаревшего snapshot.

## v1 JSON fallback

Элемент массива JSON `ingredients[]` может содержать опциональные поля:

```json
{
  "id": "...",
  "name": "Мука",
  "illustrationId": "flour-wheat",
  "illustrationPickerCleared": true
}
```

## Валидация slug (клиент)

- Если `illustrationId` не в bundled `IngredientIllustrationCatalog` → UI **Bowl**, значение в Yjs **не** менять.
- Matcher / LLM на iOS **не** реализуются в этой фиче.

## Cross-platform

| Клиент | Поведение |
|--------|-----------|
| Web edit picker | Запись как выше |
| iOS edit picker | Тот же wire |
| Web lazy-resolve | Пропускает строки с `illustrationPickerCleared` или непустым `illustrationId` |

## Тесты (обязательные)

- Round-trip parse → write → parse для обоих ключей
- Clear: отсутствие `illustrationId`, `illustrationPickerCleared == true`
- Select после clear: id восстановлен, флаг снят