# Quickstart: collection mutations (008)

## Verify build + screenshot

```bash
./scripts/verify-collection-mutations.sh
```

## Manual checks

1. **Pin** — swipe right on a row → Pin; row moves to «Закреплённые»; web shows pinned ≤ 5 s.
2. **Delete** — swipe left → Delete → confirm; row disappears; open detail for that recipe dismisses.
3. **Create** — toolbar **+** → new recipe detail in edit mode; web list shows new id (v3) ≤ 5 s.
4. **Offline** — airplane mode → pin/delete/create → reconnect → web matches ≤ 10 s.

## Key symbols

- `DocumentManager.setCollectionEntryPinned` / `tombstoneCollectionEntry` / `createRecipe`
- `YjsSyncService.setRecipePinned` / `deleteRecipeFromCollection` / `createRecipe`
- `RecipeListView` swipe actions + `recipe_list_add`