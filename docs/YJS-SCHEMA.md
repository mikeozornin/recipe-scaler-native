# Y.Doc Schema — Recipe Scaler

Exact structure of Y.Doc documents as used by the web client and server.
iOS implementation must replicate this schema exactly for binary compatibility.

Source files:
- `recipe-scaler-web/recipe-scaler/src/hooks/use-yjs-sync.ts` — recipe schema, mutations
- `recipe-scaler-web/recipe-scaler/src/utils/collection-v2.ts` — collection schema
- `recipe-scaler-web/recipe-scaler/src/utils/shopping-list-yjs.ts` — shopping list schema
- `recipe-scaler-web/shared/shopping-list/constants.ts` — shopping list key constants

## Document Types

Three document types per user, identified by doc key:

| Document | Doc Key | Description |
|----------|---------|-------------|
| Collection | `{userId}:collection` | Recipe metadata, order, tombstones |
| Recipe | `{userId}:recipe:{recipeId}` | Full recipe data |
| Shopping list | `{userId}:shoppingList` (via `documentKind`) | Shopping items |

---

## 1. Collection Document

Top-level shared type: `Y.Array('recipes')`

Each entry is a `Y.Map` with these keys:

```
Y.Array('recipes')
  └── Y.Map (per recipe)
        ├── id: string          — recipe UUID
        ├── name: string        — display name
        ├── color: string       — hex color, e.g. '#3b82f6'
        ├── imageUrl: string?   — optional image URL
        ├── updatedAt: string   — ISO 8601 timestamp
        ├── deleted: boolean    — tombstone flag (true = deleted)
        └── isPinned: boolean   — pinned to top
```

### Notes

- Deleted recipes are **not removed** from the array — they get `deleted: true` (tombstone)
- Server checks tombstones before accepting recipe updates
- Order in the array determines display order (index = position)
- `isPinned` is on the collection entry, NOT on the recipe Y.Map

### Reading

```swift
// yrs C API pseudocode
let array = ydoc_get_array(doc, "recipes")
let count = yarray_len(array, txn)
for i in 0..<count {
    let entry = yarray_get(array, txn, i)  // → Y.Map
    let id = ymap_get_str(entry, txn, "id")
    let name = ymap_get_str(entry, txn, "name")
    let deleted = ymap_get_bool(entry, txn, "deleted")
    // ...
}
```

---

## 2. Recipe Document

Two top-level shared types:

```
Y.Map('recipe')
Y.XmlFragment('description')   ← v3 only, top-level (not inside recipeMap)
```

### Y.Map('recipe') — Keys

| Key | Type | Version | Description |
|-----|------|---------|-------------|
| `name` | `string` | all | Recipe name |
| `servings` | `number` | all | Number of servings (integer ≥ 1) |
| `scaleFactor` | `number` | all | Current scale multiplier (default 1.0). **Not persisted in Yjs on web** — skip on iOS too |
| `color` | `string` | all | Hex color |
| `description` | `string` or `Y.Text` | v1/v2 | HTML description. v3: not in map, see XmlFragment below |
| `ingredients` | `Y.Array<Y.Map>` | v2/v3 | Ingredient list as Y.Array |
| `ingredients` | `string` (JSON) | v1 | Ingredient list as JSON string |
| `nutrition` | `Y.Map` or `string` (JSON) | all | Nutrition data |
| `version` | `string` | all | `'v1'`, `'v2'`, or `'v3'` |
| `isPublic` | `boolean` | all | Public visibility |
| `hasSteps` | `boolean` | all | Whether description has content |
| `createdAt` | `string` | all | ISO 8601 |
| `updatedAt` | `string` | all | ISO 8601 |
| `imageUrl` | `string?` | all | Image URL (key may be absent) |
| `imageAspectRatio` | `number?` | all | Image aspect ratio |
| `originalRecipeLink` | `string?` | all | Source URL |
| `originalRecipe` | `string?` | all | Source name |
| `_descriptionMigratedToXmlFragment` | `boolean` | v3 | Migration flag |

### Ingredients — v2/v3 format

```
Y.Array (key: 'ingredients')
  └── Y.Map (per ingredient)
        ├── id: string            — ingredient UUID
        ├── name: string          — ingredient name
        ├── amount: string        — amount with unit, e.g. "200g"
        ├── originalAmount: string — original amount before scaling
        ├── order: number         — 1-based index (auto-corrected on read)
        └── ... any additional keys
```

### Ingredients — v1 format

```
string (key: 'ingredients')
  → JSON.parse → Array<{ id, name, amount, ... }>
```

### Description — Version Differences

| Version | Storage | Editing |
|---------|---------|---------|
| v1 | `recipeMap.get('description')` as `string` | Plain text replacement |
| v2 | `recipeMap.get('description')` as `Y.Text` | HTML content in Y.Text |
| v3 | `doc.getXmlFragment('description')` — **top-level** | Tiptap via XmlFragment |

**v3 detection:**
```
isV3 = version === 'v3'
    || recipeMap.get('_descriptionMigratedToXmlFragment') === true
    || doc.getXmlFragment('description').length > 0
```

### Nutrition

Either `Y.Map` with string keys and primitive values, or `string` (JSON).

```
Y.Map (key: 'nutrition')    — OR —  string (JSON)
  ├── calories: number
  ├── protein: number
  ├── fat: number
  ├── carbs: number
  └── ... custom fields
```

---

## 3. Shopping List Document

Top-level shared type: `Y.Map('shopping')`

Constants: `SHOPPING_ROOT_MAP_KEY = 'shopping'`, `SHOPPING_ITEMS_KEY = 'items'`, `SHOPPING_META_KEY = 'meta'`

```
Y.Map('shopping')
  ├── items: Y.Array<Y.Map>
  │     └── Y.Map (per item)
  │           ├── id: string
  │           ├── label: string
  │           ├── recipeId: string | null
  │           ├── ingredientId: string | null
  │           ├── recipeName: string
  │           ├── purchased: boolean
  │           ├── purchasedAt: number?   — timestamp
  │           └── createdAt: number?     — timestamp
  │
  └── meta: Y.Map
        ├── sortMode: 'recipe' | 'alphabet'
        └── schemaVersion: number       — currently 1
```

### Initialization

If `items` or `meta` keys are missing, create them:

```swift
let root = ydoc_get_map(doc, "shopping")
if ymap_get(root, txn, "items") == nil {
    ymap_set(root, txn, "items", newYArray())
}
if ymap_get(root, txn, "meta") == nil {
    let meta = newYMap()
    ymap_set(meta, txn, "sortMode", "recipe")
    ymap_set(meta, txn, "schemaVersion", 1)
    ymap_set(root, txn, "meta", meta)
}
```

---

## Version Negotiation

Web client writes version to recipe on first edit:

```
v1: no 'version' key or version === 'v1'
v2: version === 'v2', ingredients as Y.Array<Y.Map>, description as Y.Text
v3: version === 'v3', description as XmlFragment
```

iOS should:
1. Read `version` from recipeMap
2. If absent, treat as v1
3. Write `version: 'v2'` or `'v3'` when creating new recipes
4. Handle all three formats for reading

---

## Server Protocol

### Socket.IO Events

| Event | Direction | Payload |
|-------|-----------|---------|
| `auth` | client → server | `{ userId, deviceId }` |
| `load_document` | client → server | `{ recipeId }` |
| `load_documents` | client → server | `{ recipeIds: string[] }` |
| `document_loaded` | server → client | `{ recipeId, yjsState: number[], lastSyncedAt }` |
| `documents_loaded` | server → client | `{ documents: [{ recipeId, yjsState, lastSyncedAt, imageUrl? }] }` |
| `sync_request` | client → server | `{ recipeId, yjsUpdate: number[], lastSyncedAt?, documentKind? }` |
| `sync_confirmed` | server → client | `{ recipeId, lastSyncedAt, documentKind? }` |
| `sync_error` | server → client | `{ error: string, recipeId? }` |
| `recipe_updated` | server → client (broadcast) | `{ recipeId, yjsUpdate: number[], origin? }` |
| `collection_updated` | server → client (broadcast) | `{ yjsUpdate: number[], origin? }` |
| `shopping_list_updated` | server → client (broadcast) | `{ yjsUpdate: number[], origin? }` |

### Update Format

Binary updates serialized as `Array<number>` (not Uint8Array) over Socket.IO JSON.
Convert: `Array.from(uint8Array)` before sending, `new Uint8Array(array)` after receiving.

### lastSyncedAt

- Sent by client in `sync_request` (from local SQLite)
- Used for monitoring only, **not** for conflict resolution
- CRDT resolves conflicts automatically
- `sync_error` reasons: ownership failure, tombstone, empty/invalid update — not CRDT conflicts

### Debounce

Web client debounces local updates:
- Accumulates updates in pending buffer
- Flushes every 1 second
- Merges pending updates with `Y.mergeUpdates`

iOS should replicate this behavior to avoid network chatter.

---

## Migration Notes (v1 → v2 → v3)

When creating or upgrading recipes:

**v1 → v2:**
- `ingredients`: JSON string → `Y.Array<Y.Map>`
- `description`: plain string → `Y.Text`

**v2 → v3:**
- `description`: `Y.Text` → `Y.XmlFragment` (top-level, not in recipeMap)
- Set `_descriptionMigratedToXmlFragment: true`
- Set `version: 'v3'`
- Migration is done by Tiptap Collaboration extension on web

**iOS strategy:** Create new recipes as v2 (or v3 if XmlFragment is available).
Read all formats, write v2+. Don't migrate existing recipes — let web client handle migration.

---

## Native (Swift) field mapping

Phase 2 parsers live in `RecipeScalerNative/Services/YjsSync/DocumentManager.swift` and map wire keys to:

### `CollectionEntry` ← `Y.Array('recipes')` entry `Y.Map`

| Y.Map key | Swift property | Type |
|-----------|----------------|------|
| `id` | `id` | `String` |
| `name` | `name` | `String` |
| `color` | `color` | `String` |
| `imageUrl` | `imageUrl` | `String?` |
| `updatedAt` | `updatedAt` | `String` |
| `deleted` | `deleted` | `Bool` |
| `isPinned` | `isPinned` | `Bool` |

Doc key: `{userId}:collection`

### `RecipeData` ← `Y.Map('recipe')`

| Y.Map key | Swift property | Notes |
|-----------|----------------|-------|
| `name` | `name` | string |
| `servings` | `servings` | int |
| `color` | `color` | string |
| `version` | `version` | `v1` / `v2` / `v3` |
| `description` | `description` | v1 string; v2 `Y.Text`; v3 not rendered (nil) |
| `ingredients` | `ingredients` | v1 JSON string → `[IngredientData]`; v2/v3 `Y.Array` of maps |
| `nutrition` | `nutrition` | JSON string or `Y.Map` → `NutritionData` |
| `isPublic` | `isPublic` | bool |
| `hasSteps` | `hasSteps` | bool |
| `createdAt` | `createdAt` | string |
| `updatedAt` | `updatedAt` | string |
| `imageUrl` | `imageUrl` | string? |
| `imageAspectRatio` | `imageAspectRatio` | double? |
| `originalRecipeLink` | `originalRecipeLink` | string? |
| `originalRecipe` | `originalRecipe` | string? |

Doc key: `{userId}:recipe:{recipeId}`

### `IngredientData` ← ingredient map or v1 JSON array element

| Wire key | Swift property |
|----------|----------------|
| `id` | `id` |
| `name` | `name` |
| `amount` | `amount` |
| `originalAmount` | `originalAmount` (falls back to `amount` when empty) |
| `order` | `order` |

### `NutritionData` ← `nutrition` JSON or map

| Wire key | Swift property |
|----------|----------------|
| `calories` | `calories` |
| `protein` | `protein` |
| `fat` | `fat` |
| `carbs` | `carbs` |
| (other numeric keys) | `extra` |

Scaling UI uses `originalAmount` with `servings` as base (see `RecipeDetailScaling` in `RecipeDetailViewModel.swift`).
