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

### 2026-06-02 — Native description read-only before web editor

**Decision:** Ship native read-only description rendering first (`004-description-read-only`); defer TipTap/WebKit editing to a later spec (`006-description-editor`).

**Rationale:** User narrowed scope to viewing description text on iOS first, avoiding a large WebView editor in the initial mobile parity wave.

---

### 2026-06-02 — Tab bar uses fill symbols and tint only

**Decision:** All tab items use `.fill` SF Symbols (`globe.fill`, `book.fill`, …); active vs inactive tabs are distinguished by `UITabBar` accent/gray tint only — no custom UIKit `image`/`selectedImage` outline pairs or manual selected-state icon swapping.

**Rationale:** Attempts to force outline/fill per tab via SwiftUI `Label` custom icons and UIKit configurators caused flicker after load, broken Discover icon, and conflicted with standard `UITabBar` behavior; user chose the simpler fill+color model until a fully custom tab bar is built.

---