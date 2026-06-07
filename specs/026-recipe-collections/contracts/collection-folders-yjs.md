# Contract: folders и folderIds в collection Y.Doc (026)

Sync transport — без изменений относительно [008 collection-sync](../008-collection-mutations/contracts/collection-sync.md).

## Document key

`{userId}:collection`

## Top-level keys

| Key | Type | Native read (026) | Native write (026) |
|-----|------|-------------------|---------------------|
| `recipes` | `Y.Array` | да (008+) | да (008+) |
| `folders` | `Y.Array` | да | да |

Неизвестные top-level типы не трогать.

## Folder entry `Y.Map`

| Key | Type | Required on create |
|-----|------|-------------------|
| `id` | string (UUID) | да |
| `name` | string | да (`""` если пустое имя) |
| `color` | string | да (default `oklch(0.65 0.25 270)`) |
| `createdAt` | string ISO | да |
| `updatedAt` | string ISO | да |
| `deleted` | bool | да (`false`) |

## Recipe entry — дополнительное поле

| Key | Type | Write rule |
|-----|------|------------|
| `folderIds` | `string[]` (JSON primitive array on map) | Полная замена набора; удалить ключ если пусто |

Перед записью: `validateActiveCollectionIds` — только id активных (non-deleted) папок; неизвестные/deleted id отбросить (log warning).

## Транзакции

Каждая логическая операция — **один** `doc.transact()` на collection doc.

### `createFolder`

1. `map = createFolderEntry({ id: newUUID(), name: trimmed, color? })`
2. `folders.push([map])`

### `renameFolder` / `updateFolderColor`

1. `findFolderEntry(folders, id)`
2. `set("name", …)` / `set("color", …)`
3. `set("updatedAt", nowISO)`

### `deleteFolder`

1. `folder.set("deleted", true)`, `updatedAt`
2. For each recipe entry in `recipes`:
   - if `folderId ∈ getRecipeFolderIds(entry)` → `setRecipeFolderIds(entry, ids \ {folderId})`
   - `entry.set("updatedAt", nowISO)` при изменении membership

### `setRecipeFolders(recipeId, requestedIds)`

1. Найти recipe entry по `id`
2. `validIds = validateActiveCollectionIds(doc, requestedIds)`
3. `setRecipeFolderIds(entry, validIds)`
4. `entry.set("updatedAt", nowISO)`

## Observers

После 026 native должен обновлять UI при:

- изменениях в `recipes` (в т.ч. `folderIds`)
- изменениях в `folders` (create/rename/delete без touch recipes)

## Offline queue

- `docKey`: `{userId}:collection`
- `recipeId` (queue row): `"collection"`
- Folder mutations не создают отдельных recipe doc updates

## CRDT semantics (документация для клиентов)

- Concurrent creates в `folders` — оба остаются.
- Concurrent `folderIds` на **одном** рецепте — LWW на весь массив (не union). UI assign sheet читает текущее состояние и пишет полный набор на Done.

## Do-No-Harm checklist (регрессия)

- [ ] `setCollectionEntryPinned` / `tombstoneCollectionEntry` не вызывают `remove` на `folderIds`
- [ ] `appendCollectionEntryIfNotExists` не затирает существующий entry при повторном вызове
- [ ] `applyUpdate` / snapshot restore сохраняют `folders` и `folderIds` с веба