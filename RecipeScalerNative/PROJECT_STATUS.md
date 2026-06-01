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

## Phase 3: Native Editing — NEXT

Edit recipe fields (except description) through yrs mutations.

### Scope

- [ ] Write to Y.Map: name, servings, scaleFactor, color
- [ ] Ingredient CRUD via Y.Map mutations
- [ ] Nutrition editing
- [ ] Debounced update sending (1s, same as web)
- [ ] Offline queue: store updates in SQLite, drain on reconnect

### Depends on

- Phase 2 complete
- Y.Doc schema fully mapped (see docs/YJS-SCHEMA.md)

## Phase 4: Description Editor (WKWebView + Tiptap)

Rich text editing for recipe description via embedded WebView.

## Phase 5: Full Sync Parity

Shopping list, collection mutations, recipe creation, full offline queue.

## Phase 6: Polish

QR scanner, PDF export, widgets, App Store prep.

## Architecture Evolution

```
Phase 1 (done)          Phase 2 (done)             Phase 3+ (target)
┌────────────┐     ┌─────────────────────┐    ┌──────────────────────┐
│ REST JSON  │     │  yrs Y.Doc (read)   │    │ yrs Y.Doc (read/write│
│ SwiftData  │ ──► │  + Socket.IO sync   │ ──►│ + Tiptap WebView     │
│ WS notify  │     │  + SQLite snapshots │    │ + offline queue      │
└────────────┘     └─────────────────────┘    └──────────────────────┘
```

## References

- [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- [docs/YJS-SCHEMA.md](../docs/YJS-SCHEMA.md)
- [SETUP.md](../SETUP.md)
- [specs/001-yrs-native-read/](../specs/001-yrs-native-read/)