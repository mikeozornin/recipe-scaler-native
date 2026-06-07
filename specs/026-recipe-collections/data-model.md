# Модель данных: коллекции (026)

Дополняет [008 data-model](../008-collection-mutations/data-model.md). Источник: [NATIVE_APP_COLLECTIONS.md](../../recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md) §2–6.

## Collection Y.Doc (`{userId}:collection`)

Два top-level shared type:

```
folders: Y.Array
  └─ [i]: Y.Map
       ├─ id: string (UUID)
       ├─ name: string          // пустая строка = без названия (i18n recipes.no-title)
       ├─ color: string        // default oklch(0.65 0.25 270)
       ├─ createdAt: string    // ISO 8601 UTC
       ├─ updatedAt: string
       └─ deleted: boolean     // tombstone, не удалять из массива

recipes: Y.Array
  └─ [i]: Y.Map
       ├─ … поля 008 …
       └─ folderIds?: string[] // plain array value на map, не Y.Array
```

### Активная коллекция

`deleted !== true`. Сортировка для UI: имя (case-insensitive, без ведущего emoji), tie-break `id`.

### Членство рецепта

- Ключ `folderIds` **отсутствует**, пока рецепт ни разу не назначали в коллекцию (совместимость с native 008).
- Пустой массив после нормализации → ключ **удаляется** с map.
- Рецепт без членства → «Без коллекции» (виртуальная папка).

## Swift-модели (целевые)

### `RecipeFolder`

| Поле | Тип | Примечание |
|------|-----|------------|
| `id` | `String` | UUID |
| `name` | `String` | wire; display через `FolderDisplayName` |
| `color` | `String` | |
| `createdAt` | `String` | |
| `updatedAt` | `String` | |
| `deleted` | `Bool` | не показывать в UI если true |

### `CollectionEntry` (расширение)

Добавить `folderIds: [String]` (default `[]` при чтении).

### Виртуальные папки (только UI)

| Константа | id | i18n |
|-----------|-----|------|
| `ALL_RECIPES_FOLDER_ID` | `all` | `collections.all-recipes` |
| `UNCATEGORIZED_FOLDER_ID` | `uncategorized` | `collections.uncategorized` |

Не хранятся в Yjs. Порядок на корне: `all` → user folders → `uncategorized` → create row.

## Derived index (`CollectionRecipesIndex`)

```text
liveRecipes       = entries where deleted != true
uncategorized     = liveRecipes where folderIds empty/absent
countByFolder     = Map<folderId, Int>   // рецепт считается в каждой папке из folderIds
folderRecipesById = Map<folderId, [CollectionEntry]>
```

Сортировка внутри списков: `isPinned` first, затем имя (emoji-aware), затем `id`.

## View mode (локально)

| Ключ | Значения | Default |
|------|----------|---------|
| `recipe-list-view-mode` (UserDefaults) | `flat` \| absent → collections | collections |

## Write operations (сводка)

| Действие | Yjs |
|----------|-----|
| Create folder | `folders.push([new Map])` |
| Rename / recolor | `folderMap.set("name"…)`, `updatedAt` |
| Delete folder | `deleted: true` + strip id из всех `folderIds` |
| Set recipe folders | `setRecipeFolderIds(entry, validIds)` |
| Pin / delete recipe (008) | только известные ключи; **не трогать** `folderIds` |

Детали транзакций: [contracts/collection-folders-yjs.md](contracts/collection-folders-yjs.md).