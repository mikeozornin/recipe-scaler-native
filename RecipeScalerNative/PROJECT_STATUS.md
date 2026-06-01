# RecipeScalerNative — Project Status

## Phase 1: Read-only MVP — DONE

Read-only iOS app using REST + WebSocket notifications. No CRDT on device.

### Completed

- [x] SwiftData models (Recipe, Ingredient, RecipeTimer)
- [x] REST API client (GET /api/recipes-v1/)
- [x] WebSocket notifications (Socket.IO)
- [x] Recipe list with search
- [x] Recipe detail view
- [x] Ingredient scaling (slider)
- [x] Localization (ru/en)
- [x] Seed-based auth (BIP39 + Keychain)
- [x] Timers with background execution + local notifications
- [x] Device ID management

### Files: 13 Swift + documentation

## Phase 2: yrs Integration — NEXT

Add yrs CRDT engine and YjsSyncService. Native read from Y.Doc, no editing yet.

### Scope

- [ ] Compile yrs as XCFramework (Rust → C FFI → Swift)
- [ ] Swift wrapper over yrs C API (yffi)
- [ ] YjsSyncService: connect, auth, load_document, sync_request
- [ ] Y.Doc lifecycle: create, applyUpdate, encodeStateAsUpdate
- [ ] Collection document: read Y.Array('recipes'), render list
- [ ] Recipe document: read Y.Map('recipe'), render detail
- [ ] SQLite persistence: state snapshots + lastSyncedAt
- [ ] Migrate recipe list to use Y.Doc data instead of REST JSON

### Risks

- yrs XmlFragment API coverage — verify with real v3 recipe data
- XCFramework build pipeline for arm64 + x86_64 + simulator

## Phase 3: Native Editing

Edit recipe fields (except description) through yrs mutations.

### Scope

- [ ] Write to Y.Map: name, servings, scaleFactor, color
- [ ] Ingredient CRUD via Y.Map mutations
- [ ] Nutrition editing
- [ ] Debounced update sending (1s, same as web)
- [ ] Observer → SwiftUI reactive updates
- [ ] Offline queue: store updates in SQLite, drain on reconnect

### Depends on

- Phase 2 complete
- Y.Doc schema fully mapped (see docs/YJS-SCHEMA.md)

## Phase 4: Description Editor (WKWebView + Tiptap)

Rich text editing for recipe description via embedded WebView.

### Scope

- [ ] Bundle Tiptap + custom extensions (TimerNode, IngredientNode, HeadingWithHash)
- [ ] WKWebView component for description block
- [ ] Bridge: Swift ↔ WKWebView via [UInt8] updates
- [ ] yrs → WKWebView: initial XmlFragment state
- [ ] WKWebView → yrs: user edits as Yjs updates
- [ ] Remote updates → WKWebView: apply incoming changes
- [ ] getHTML() for sharing / export
- [ ] v2/v1 description fallback (Y.Text → plain text)

### Depends on

- Phase 2 (yrs with XmlFragment support)
- Tiptap bundle build (webpack/esbuild)

## Phase 5: Full Sync Parity

Complete sync features matching web client.

### Scope

- [ ] Shopping list: Y.Map('shopping') + items + meta
- [ ] Collection mutations: add/delete/pin recipes
- [ ] Tombstone handling (deleted recipes in collection)
- [ ] Recipe creation (new Y.Doc + collection entry)
- [ ] Offline resilience: conflict-free merge after reconnect
- [ ] Image upload (existing REST endpoint)
- [ ] Push notifications as sync triggers (not data channel)

## Phase 6: Polish

- [ ] QR scanner/generator for auth
- [ ] PDF export
- [ ] Import from URL
- [ ] Widgets
- [ ] Siri Shortcuts
- [ ] App Store preparation

## Architecture Evolution

```
Phase 1 (done)          Phase 2-3 (next)           Phase 4+ (target)
┌────────────┐     ┌─────────────────────┐    ┌──────────────────────┐
│ REST JSON  │     │  yrs Y.Doc (read)   │    │ yrs Y.Doc (read/write│
│ SwiftData  │ ──► │  + Socket.IO sync   │ ──►│ + Tiptap WebView     │
│ WS notify  │     │  + SQLite snapshots │    │ + offline queue      │
└────────────┘     └─────────────────────┘    │ + shopping list      │
                                               └──────────────────────┘
```

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| CRDT engine | yrs (Rust) via C FFI | Binary-compatible with Yjs, 2k+ stars, not yswift (89 stars, WIP) |
| Description editor | WKWebView + Tiptap | Custom Tiptap nodes impractical to rewrite natively |
| Sync transport | Socket.IO (same as web) | No backend changes needed |
| Local storage | SQLite | Y state snapshots + offline queue |
| Auth | Seed-based (BIP39) | Same as web, no password needed |
| UI framework | SwiftUI | Modern, native, declarative |

## References

- [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) — target architecture
- [docs/YJS-SCHEMA.md](../docs/YJS-SCHEMA.md) — Y.Doc structure
- [SETUP.md](../SETUP.md) — build instructions
