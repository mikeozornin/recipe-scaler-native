# Project decisions

Chronological log of substantive choices (newest last).

### 2026-06-01 — Spec Kit artifacts in Russian

**Decision:** Feature artifacts under `specs/<feature>/` (`spec.md`, `plan.md`, `research.md`, `data-model.md`, `tasks.md`, `quickstart.md`, `contracts/`) are written in Russian.

**Rationale:** Explicit user request during Spec Kit setup for this repo; keeps specs aligned with the author's working language and existing SPECKIT section in `AGENTS.md`.

---

### 2026-06-01 — Mobile app uses production API

**Decision:** The iOS app targets `https://recipe-scaler.ru` for real-device use, not developer `localhost`.

**Rationale:** A phone cannot reach the Mac's local dev server; user confirmed the app works against production after switching away from localhost.

---

### 2026-06-01 — Legacy recipe formats read-only on iOS

**Decision:** Recipes older than v3 (v1/v2) are read-only in the native app with a legacy banner; migration to v3 is performed only in the web app.

**Rationale:** User chose to drop native editing support for obsolete schemas and centralize migration in web, reducing native scope while keeping read access.

---

### 2026-06-01 — Replace local collection snapshot on server load

**Decision:** When the server sends a full collection via `document_loaded`, replace the local Y.Doc snapshot (`replaceDocument`) instead of merging with a cached SQLite snapshot.

**Rationale:** Deleted recipes from web remained visible on iOS because stale local collection data was merged with fresher server state; server collection is the source of truth after load.

---

### 2026-06-01 — Socket.IO websocket-only on iOS

**Decision:** Configure the iOS Socket.IO client with `forceWebsockets(true)`, aligned with the web Yjs client, instead of relying on long-polling transport.

**Rationale:** Polling connections failed with `NSURLError -1005`, broke reconnect, and caused auth/sync to emit before the socket was ready; websocket-only stabilized sync on device.

---

### 2026-06-01 — Offline-first recipe images via API then disk cache

**Decision:** Recipe images are downloaded through the API and persisted to a local disk cache so list and detail views work offline after first fetch (feature `003-recipe-image-offline-cache`).

**Rationale:** User defined the app as offline-first; thumbnails and full-size images must not require network on repeat opens.

---

### 2026-06-10 — Inline recipe description edit (019)

**Decision:** v3 description editing uses one Edit mode on `YDocRecipeDetailView` with a shared ScrollView (ingredients then instructions), inline WKWebView + Tiptap, native sticky bottom formatting bar wired via bridge v2 (`command` / `selectionState`), embedded WebView height with focus mode above 2000 pt; sheet `DescriptionEditorView` deprecated.

**Rationale:** Matches mobile web stacked flow; avoids context switch; native toolbar for HIG/a11y; manages WebView height without a second screen.

---

### 2026-06-02 — Native description read-only before web editor

**Decision:** Ship native read-only description rendering first (`004-description-read-only`); defer TipTap/WebKit editing to a later spec (`006-description-editor`).

**Rationale:** User narrowed scope to viewing description text on iOS first, avoiding a large WebView editor in the initial mobile parity wave.

---

### 2026-06-02 — Tab bar uses fill symbols and tint only

**Decision:** All tab items use `.fill` SF Symbols (`globe.fill`, `book.fill`, …); active vs inactive tabs are distinguished by `UITabBar` accent/gray tint only — no custom UIKit `image`/`selectedImage` outline pairs or manual selected-state icon swapping.

**Rationale:** Attempts to force outline/fill per tab via SwiftUI `Label` custom icons and UIKit configurators caused flicker after load, broken Discover icon, and conflicted with standard `UITabBar` behavior; user chose the simpler fill+color model until a fully custom tab bar is built.

---

### 2026-06-06 — Apple Reminders as mirrored shopping-list copy

**Decision:** On iOS, Apple Reminders is a synced mirror of the CRDT shopping list (server remains source of truth for web/MCP/public share). Sync is bidirectional for completion state; completed items stay in Reminders as checked, not deleted. Reminders item notes use localized strings.

**Rationale:** User wants native Reminders integration without breaking web shopping list or cross-device CRDT sync. Deleting checked items would lose history in Reminders; mirror model keeps web unchanged while giving iOS users their preferred list app.

---

### 2026-06-06 — Timer push: server sync required, toggle hidden until APNs

**Decision:** Do not ship a local-only timer notification fallback without server push sync. Hide the profile push-notification toggle until APNs registration works with the paid Developer Program and backend contract (`specs/023-push-notifications`).

**Rationale:** User rejected unsynced local notifications as a substitute for web-style timer push. Personal Team cannot enable Push Notifications capability; partial UX would mislead users.

---

### 2026-06-06 — xcstrings typograf preserves Xcode formatting

**Decision:** The native typograf script edits `Localizable.xcstrings` with surgical per-line value replacement instead of `JSON.parse` → `JSON.stringify`.

**Rationale:** Xcode String Catalog uses non-standard JSON formatting (space before colon, empty-string placeholders, no trailing newline). A full round-trip rewrites the entire file and creates noisy diffs Xcode would immediately undo.

---

### 2026-06-07 — Collections optional folder grid view

**Decision:** Collections screen supports an optional display mode: list or folder grid (user-toggleable). Virtual folders (`all`, `uncategorized`) render as folders; empty collections use outline folder icon with folder accent color; recipe count shown under folder name.

**Rationale:** User requested iOS-adapted folder visualization matching a reference mockup while keeping list mode for users who prefer the compact layout.

---

### 2026-06-07 — Collection rename uses Cancel/Done toolbar

**Decision:** Renaming a collection folder uses an inline rename field with **Cancel** (leading) and **Done** (trailing) in the navigation bar, auto-focus with select-all, and hides the back button and ellipsis menu while editing.

**Rationale:** Initial inline-rename pattern felt non-native on iOS; user explicitly chose the standard modal-editing toolbar pattern over keeping navigation chrome visible during rename.

---

### 2026-06-07 — Folder color picker: preset grid in rename toolbar

**Decision:** Collection folder color editing uses a preset color grid embedded in the rename toolbar (web palette parity, iOS presentation), not a separate settings screen or free-form color wheel.

**Rationale:** User chose preset grid + toolbar placement when asked how to adapt web folder color editing to iOS; keeps the edit flow in one place alongside rename.

---

### 2026-06-07 — Recipe ellipsis menu: no separator before Delete

**Decision:** The recipe detail actions menu matches web item order (e.g. cart, pin) but **without** a separator immediately before Delete.

**Rationale:** User explicitly removed the separator after initial web-parity implementation; final layout is web order minus that divider.

---

### 2026-06-08 — Production push after Live Activities

**Decision:** Ship Live Activities / Dynamic Island for timers before enabling production APNs push notifications. Document in `docs/PAID-APPLE-DEVELOPER-REQUIRED.md` that push capability in the portal comes after Activity Charts work.

**Rationale:** User wants to test timer visibility on lock screen first; push registration requires paid Developer Program and should follow the Activity Charts milestone, not precede it.

---

### 2026-06-10 — Yjs schema mismatch: native bridge writes elements, web tiptap expects marks

**Decision:** Document the mismatch; fix is deferred to a separate task. The native `description-editor-bridge.js` `collectInlineNodes()` writes bold/italic/highlight/strike/link as `Y.XmlElement` wrappers (e.g. `<bold>text</bold>`), but the web's tiptap ProseMirror schema defines these as **marks** (inline formatting attributes), not nodes. Additionally, native creates `Y.XmlElement('ingredient')` with text children, but the web `IngredientNode` is `atom: true` (no children). This causes the web recipe view to crash when rendering recipes edited on native.

**Rationale:** Proper fix requires rewriting the native bridge to use `Y.XmlText` with formatting marks instead of wrapping elements — a significant refactor of the Yjs sync layer. The web crash is real but the fix scope is too large for the current style-parity batch. A dedicated task should rewrite `collectInlineNodes()` and `renderXmlText()` in the bridge JS to produce Yjs output compatible with ProseMirror's mark system.

---