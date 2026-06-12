# yrs C API — поверхность записи (Phase 3)

**Дата**: 2026-06-01  
**Расширяет**: [001-yrs-native-read/contracts/yffi-api.md](../../001-yrs-native-read/contracts/yffi-api.md)

## Область

Операции записи для документов рецепта v3. Read API Phase 2 без изменений.

## Новые модули Swift

| Файл | Ответственность |
|------|-----------------|
| `YrsInput.swift` | Сборка `YInput` для string, int, double, bool, ссылок на вложенные map/array |
| `YrsMap+Write.swift` или extensions | `set(key:txn:value:)`, `remove(key:txn:)` |
| `YrsArray+Write.swift` | `insert(map:txn:at:)`, `remove(index:txn:len:)` |

## Обязательные C-функции

| Функция | Использование в Phase 3 |
|---------|-------------------------|
| `ydoc_write_transaction` | Уже в Phase 2 для `applyUpdate` |
| `ymap_insert` | `name`, `servings`, `color`, поля map ингредиента, nutrition |
| `yarray_insert_range` | append / insert `Y.Map` ингредиента |
| `yarray_remove_range` | удаление ингредиента по индексу |
| `ytype_get` | разрешение веток `recipe`, `ingredients` в write txn |
| `ytransaction_commit` | commit после batch insert в одном действии пользователя |
| `ytransaction_state_diff_v1` | blob апдейта для `sync_request` |

## Debounce merge (не в libyrs)
`ytransaction_merge_updates_v1` / `ymerge_updates` **отсутствуют** в текущем `libyrs.h`. `UpdateDebouncer` не мержит pending updates в один blob: очередь + последовательные `sync_request`. Не использовать `state_diff_v1` на пустом throwaway doc для merge инкрементальных апдейтов — даёт no-op. Паритет с вебом по `Y.mergeUpdates` — отдельная задача (JS bundle или порт алгоритма).

## Паттерн write-транзакции

```swift
try await doc.withWriteTransaction { _, txn in
    let recipeMap = ytype_get(txn, "recipe")
    YrsMap(branch: recipeMap).set(key: "name", value: .string(newName), txn: txn)
    // ...
}
let update = await doc.encodeStateAsUpdate()
```

## Origin

`ydoc_write_transaction(doc, 0, NULL)` (как в Phase 2 apply), пока не потребуется origin tagging как на вебе.

## Память

- Каждый `YInput` / вложенная структура — правила destroy yffi из контракта Phase 2
- Одна write txn на **commit** пользователя (Done, Save в sheet, удаление ингредиента)

## Вне scope

- `ytext_insert` / запись XmlFragment (Phase 4)
- мутации `ymap` документа коллекции
- перезапись v1 JSON string `ingredients`