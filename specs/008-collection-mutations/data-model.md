# Collection entry write paths (008)

## Collection Y.Doc

```
recipes: Y.Array
  └─ [i]: Y.Map
       ├─ id: string
       ├─ name: string
       ├─ color: string
       ├─ imageUrl?: string
       ├─ updatedAt: string (ISO8601)
       ├─ deleted: bool
       └─ isPinned: bool
```

## Write operations

| Action | API | Fields touched |
|--------|-----|----------------|
| Pin | `setCollectionEntryPinned` | `isPinned`, `updatedAt` |
| Unpin | same | `isPinned: false` |
| Delete | `tombstoneCollectionEntry` | `deleted: true`, `updatedAt` |
| Create | `createRecipe` | new array entry + new `{userId}:recipe:{id}` v3 map |

## Recipe doc on create (v3)

`Y.Map('recipe')`: `id`, `name`, `version: "v3"`, `servings: 1`, `color`, `createdAt`, `updatedAt`, `ingredients: []`, `isPublic: false`  
Top-level `Y.XmlFragment('description')` ensured empty.

## Display filter

`collectionEntries` = all entries where `deleted != true` (unchanged from phase 1).