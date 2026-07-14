# Y.Doc Schema — Recipe Scaler

> **Канон (shared):**  
> [`../../recipe-scaler-web/specs/shared/yjs-schema.md`](../../recipe-scaler-web/specs/shared/yjs-schema.md)  
> Sync: [`../../recipe-scaler-web/specs/shared/sync-protocol.md`](../../recipe-scaler-web/specs/shared/sync-protocol.md)

Ниже — **native-only** mapping (Swift). Wire keys/types must match shared schema.

## Native (Swift) field mapping

Parsers: `RecipeScalerNative/Services/YjsSync/` (`DocumentManager` and readers).

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
| `folderIds` | `folderIds` | `[String]` (optional; 026) |

### `RecipeFolder` ← `Y.Array('folders')` entry `Y.Map` (026)

| Y.Map key | Swift property | Type |
|-----------|----------------|------|
| `id` | `id` | `String` |
| `name` | `name` | `String` |
| `color` | `color` | `String` |
| `createdAt` | `createdAt` | `String` |
| `updatedAt` | `updatedAt` | `String` |
| `deleted` | `deleted` | `Bool` |

Doc key: `{userId}:collection`

### `RecipeData` ← `Y.Map('recipe')`

| Y.Map key | Swift property | Notes |
|-----------|----------------|------|
| `name` | `name` | string |
| `servings` | `servings` | int |
| `color` | `color` | string |
| `version` | `version` | `v1` / `v2` / `v3` |
| `description` | `description` | v1 string; v2 `Y.Text`; v3 not in map (XmlFragment) |
| `ingredients` | `ingredients` | v1 JSON / v2–v3 `Y.Array` |
| `nutrition` | `nutrition` | JSON or `Y.Map` |
| `isPublic` | `isPublic` | bool |
| `hasSteps` | `hasSteps` | bool |
| `createdAt` / `updatedAt` | same | string |
| `imageUrl` | `imageUrl` | string? |
| `imageAspectRatio` | `imageAspectRatio` | double? |
| `originalRecipeLink` / `originalRecipe` | same | string? |

Doc key: `{userId}:recipe:{recipeId}`

### `IngredientData`

| Wire key | Swift |
|----------|-------|
| `id`, `name`, `amount`, `originalAmount`, `order` | same |
| `illustrationId` | optional (043) |

### Platform notes

- UUID ids: **lowercase** (shared rule).
- `YrsDocument` sets `Y_SKIP_GC` on recipe docs (y-prosemirror / yjs 13 skip structures).
- `scaleFactor` — do not persist in Yjs (shared).
- Do-No-Harm: preserve unknown keys (especially `folderIds`).
- Collections UI guide: `../recipe-scaler-web/llm/NATIVE_APP_COLLECTIONS.md`
