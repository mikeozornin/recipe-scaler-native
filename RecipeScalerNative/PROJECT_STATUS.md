# RecipeScalerNative — Project Status

## Phase 1: Read-only MVP — DONE

Read-only iOS app using REST + WebSocket notifications. No CRDT on device.

### Completed

- [x] SwiftData models (Recipe, Ingredient, RecipeTimer)
- [x] REST API client (GET /api/recipes-v1/) — list/detail removed in Phase 2; images + auth remain
- [x] WebSocket notifications (Socket.IO) — replaced by YjsSyncService in Phase 2
- [x] Recipe list with search
- [x] Recipe detail view
- [x] Ingredient scaling (slider)
- [x] Localization (ru/en)
- [x] Seed-based auth (BIP39 + Keychain)
- [x] Timers with background execution + local notifications
- [x] Device ID management

## Phase 2: yrs Integration — DONE (read-only)

Native read from Y.Doc via yrs + Socket.IO. No editing mutations yet.

### Completed

- [x] `YrsXCFramework.xcframework` build script (`scripts/build-yrs-xcframework.sh`)
- [x] Swift wrapper: `YrsDocument`, `YrsMap`, `YrsArray`, `YrsText`, `YrsValue`, `YrsObserver`
- [x] `YjsSyncService` + `SyncEventHandler` + `DocumentManager`
- [x] Socket.IO: `auth`, `load_document`, `document_loaded`, `collection_updated`, `recipe_updated`, `sync_error`
- [x] Collection list from `Y.Array('recipes')`
- [x] Recipe detail from `Y.Map('recipe')` (v1/v2/v3 read paths)
- [x] GRDB SQLite snapshots (`ydoc_snapshots.sqlite`)
- [x] Offline-first list load from SQLite; `loadRecipe` restores from snapshot
- [x] `yobserve_deep` → reactive `@Published` updates
- [x] Ingredient scaling from `originalAmount` / servings

### Remaining manual check

- [ ] SC-002 parity: compare v1/v2/v3 sample recipes with web client (T031a)

## Phase 3: Native Editing — DONE

Edit v3 recipe fields (except description) through yrs mutations, debounced sync, offline queue.

### Completed

- [x] `RecipeEditPolicy` — v3-only writes; v1/v2 read-only + `RecipeLegacyBanner`
- [x] yrs write API: `YrsInput`, `YrsMap`/`YrsArray` mutations, `YrsDocument` local updates
- [x] `DocumentManager` — name, servings, color, ingredient CRUD, nutrition map
- [x] `UpdateDebouncer` (~1 s) + `sync_request` / `sync_confirmed`
- [x] SQLite `offline_sync_queue` + `OfflineWriteQueue`; drain on reconnect; purge on user change
- [x] UI: `YDocRecipeDetailView` edit mode, `RecipeEditToolbar`, `IngredientEditSheet`
- [x] `sync_error` → localized alerts; tombstone removes recipe and pops navigation

### Manual validation (see `specs/002-native-editing/quickstart.md`)

- [ ] iOS → web field parity with live backend + web client
- [ ] Offline edit → reconnect → web within 10 s
- [ ] Debounce: ≤2 `sync_request` per 10 s rapid typing

### Out of scope (later phases)

- Description rich-text editor (Phase 4)
- Collection create/delete, shopping list (Phase 5)

## Spec 003: Recipe image offline cache — DONE

REST download → disk cache (`preview` + `full`); UI reads local files only. Parity with web `imageVersionToken`.

### Completed

- [x] `RecipeImageService` — `ensureCached`, two-phase prefetch (previews then full), version-aware invalidation
- [x] `ImageCacheService` + `RecipeImageDiskCache` / `RecipeImageDecoder` / display cache
- [x] List + detail via `RecipeCachedImageView`; no `AsyncImage` on Y.Doc `imageUrl`
- [x] Offline: no network when disconnected; stale local file OK until reconnect
- [x] `SyncStatusSheet` — cache status in sync UI
- [x] Unit tests + `scripts/verify-offline-images.sh`

### Manual validation (`specs/003-recipe-image-offline-cache/quickstart.md`)

- [x] Online previews in list after collection sync
- [x] Offline list + full header image after prefetch (airplane mode, relaunch)
- [x] Web photo change / delete → iOS updates after sync (verified 2026-06-02)

## Spec 004: Description read-only — DONE (verified 2026-06-02)

Native v3 `XmlFragment('description')` → HTML via yrs; existing `StepsSection`. No Tiptap / WKWebView.

- [x] `XmlFragmentToHTML` + `DocumentManager` v3 read path
- [x] Simulator verify: `scripts/verify-recipe-description-native.sh` (recipe `7daed53b`, screenshot + `description_html_ready` / `readRecipeData_done`)
- [x] Manual quickstart (`specs/004-description-read-only/quickstart.md`) — automated path covers US1; offline/web regression still manual

## Phase 4b: Description Editor (planned as 005)

Rich text **editing** for recipe description (WKWebView + Tiptap or alternative).

## Phase 5: Full Sync Parity

Shopping list, collection mutations, recipe creation, full offline queue.

## Phase 6: Polish

QR scanner, PDF export, widgets, App Store prep.

## Architecture Evolution

```
Phase 1 (done)          Phase 2 (done)             Phase 3 (done)
┌────────────┐     ┌─────────────────────┐    ┌──────────────────────┐
│ REST JSON  │     │  yrs Y.Doc (read)   │    │ yrs Y.Doc (read/write│
│ SwiftData  │ ──► │  + Socket.IO sync   │ ──►│ + offline write queue│
│ WS notify  │     │  + SQLite snapshots │    │ + debounced sync     │
└────────────┘     └─────────────────────┘    └──────────────────────┘
```

## References

- [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- [docs/YJS-SCHEMA.md](../docs/YJS-SCHEMA.md)
- [SETUP.md](../SETUP.md)
- [specs/001-yrs-native-read/](../specs/001-yrs-native-read/)
- [specs/002-native-editing/](../specs/002-native-editing/)
- [specs/003-recipe-image-offline-cache/](../specs/003-recipe-image-offline-cache/)
- [specs/004-description-read-only/](../specs/004-description-read-only/)