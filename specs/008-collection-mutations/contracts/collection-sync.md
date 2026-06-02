# Collection sync contract (008)

## Document key

`{userId}:collection`

## Socket.IO

| Event | Direction | Payload |
|-------|-----------|---------|
| `load_document` | client → server | `{}` (no `recipeId`; optional `documentKind: "collection"` on server) |
| `collection_updated` | server → client | `{ yjsUpdate: number[] }` |
| `sync_request` | client → server | `{ yjsUpdate: number[], lastSyncedAt?: string }` — **omit** `recipeId` (same as web `recipeId: undefined`) |
| `sync_confirmed` | server → client | collection ack (no per-recipe write state on iOS) |

## Offline queue

- `docKey`: `{userId}:collection`
- `recipeId` (queue row): `"collection"`
- On create recipe: also enqueue `{userId}:recipe:{id}` with `recipeId` = UUID

## Local write → sync

1. `DocumentManager` mutates `Y.Array('recipes')` or appends entry.
2. `deliverPendingLocalUpdate(recipeId: "collection")` encodes doc → `YjsSyncService.handleLocalRecipeUpdate`.
3. Debounced `sync_request` when online; `OfflineWriteQueue` when offline.