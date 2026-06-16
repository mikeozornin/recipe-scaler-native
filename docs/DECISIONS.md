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

**Update (2026-06-12):** Recipe documents follow **offline-first / web parity** (see decision below). Collection still uses merge-via-`applyUpdate` when local state exists, matching `yjs-client.ts`; full `replaceDocument` only when local snapshot is empty.

---

### 2026-06-12 — Offline-first Yjs writes on iOS (web parity)

**Decision:** Native editing is **offline-first**: every local mutation is applied to the in-memory Y.Doc and persisted to SQLite immediately; Socket.IO `sync_request` and `offline_sync_queue` only **distribute** CRDT updates outward. Incoming `document_loaded` / `recipe_updated` **merge** into local state (`applyUpdate`), never replace a recipe doc that has unsynced local changes. `load_document` is skipped while a recipe has pending offline queue entries or `WriteSyncState` ∈ {`pendingLocal`, `syncing`, `queued`}.

**Rationale:** Matches PWA `yjs-client.ts` (IndexedDB first, then sync). Fixes lost description edits when the socket stayed `connected` during airplane mode or when `load_document` replaced a newer local snapshot with stale server state.

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

**Update (2026-06-12):** Fix path is full Tiptap migration (see decision below), not patching `collectInlineNodes()` in the contentEditable bridge.

---

### 2026-06-12 — Native description editor: migrate to Tiptap on yjs 13

**Decision:** Replace the custom `contentEditable` + reconcile bridge (`description-editor-bridge.js`) with the same Tiptap / y-prosemirror stack as web (yjs **13**, not 14). Abandon maintaining the bespoke native editor. Set `Y_SKIP_GC` on native yrs recipe docs so garbage-collection skip structures are not emitted (y-prosemirror on yjs 13 cannot integrate skips; yjs 14 has skip support but no working ProseMirror binding).

**Rationale:** Custom editor syncs plain text but breaks structural edits (nested lists, mid-document insert, offline duplication). It amplified CRDT history by recreating full HTML on each keystroke, forcing yrs skip GC. Tiptap applies incremental ProseMirror ops like web, sharply reducing that risk. User explicitly chose yjs 13 + Tiptap over continuing to patch contentEditable or waiting for yjs 14.

---

### 2026-06-12 — Timer Live Activities (spec 026)

**Decision:** One Live Activity per active timer on Lock Screen; system semantic colors (`primary` / `orange` / `red`); edge-to-edge progress overlay; pause/resume via `LiveActivityIntent` + App Group action queue; deep link tap opens recipe via `recipe-scaler://recipe/{id}`.

**Rationale:** Implements the milestone deferred before production APNs (see 2026-06-08). Per-timer activities chosen for v1 despite HIG preference for a single rotating activity; coordinator allows consolidating later.

---

### 2026-06-12 — Agent debug logging: sandbox NDJSON file, not localhost ingest on device

**Decision:** Agent/debug logs write to `Library/Application Support/debug-session.ndjson` on both simulator and physical device. Do not rely on `127.0.0.1` HTTP ingest from a physical iPhone.

**Rationale:** On device, localhost is the phone itself — Cursor ingest on the Mac is unreachable. Unified file + pull gives parity.

**Superseded (2026-06-16):** logging disabled-by-default and `AGENT_DEBUG_LOG_ENABLED` — см. решение ниже про `AppLog`.

---

### 2026-06-16 — Unified AppLog facade (spec 028)

**Decision:** Single `AppLog` facade for all app logging. DEBUG builds write NDJSON to `Library/Application Support/debug-session.ndjson` **by default** (no scheme env required). Opt-out: `AGENT_DEBUG_LOG_DISABLED=1`. All builds mirror to `os.Logger`. `AgentSyncDebugLog` / `DebugSessionNDJSONLog` / `CursorDebugIngestLog` remain as thin compatibility wrappers. Agent pulls logs via `scripts/pull-app-logs.sh`; user exports from Profile → Diagnostics on device. Release: no file; profile shows a clear «no log» message.

**Rationale:** Fragmented logging (`AgentSyncDebugLog` only in Views, `print`/`Logger` in Services) made agent reproduction unreliable. Default-on DEBUG logging works on simulator and phone without env injection; rotation caps disk use (5 MB × 3 archives).

**Docs:** `llm/how-to-debug.md`, `docs/AGENT-WORKFLOW.md` §Отладка, `AGENTS.md` §Журналирование.

---

### 2026-06-14 — Discover section enabled (spec 017)

**Decision:** Enable the Discover tab and full Discover flow on iOS (curated collections, public profiles, read-only recipe preview, preview images, tokenized search). Adapt navigation to iOS HIG; keep Import as a 5th tab that opens a sheet (web parity). Deep links deferred.

**Rationale:** Feature was implemented in spec 011 but commented out; user requested full spec 017 enablement with iOS-native navigation rather than a minimal uncomment-only rollout.

---

### 2026-06-14 — Live Activity: always dark card on Lock Screen

**Decision:** Timer Live Activities on the Lock Screen always use an explicit black `containerBackground` and light foreground text, regardless of system color scheme, DND/Focus dimming, or widget rendering mode.

**Rationale:** On device, DND-dim exposes stale `colorScheme == .light` in the widget extension (FB15148099) while the card chrome is dark; semantic/adaptive colors produced black-on-black or white-on-white. User chose a single fixed dark-card appearance for all skins and modes after verifying DND fix.

---

### 2026-06-14 — AI Assistant: iOS-native release scope

**Decision:** Ship assistant release minimum with iOS-native patterns only — voice via `AVAudioRecorder`, offline disabled composer, FAB inset above tab bar/timer panel — without blind web UI copy (no web-style tool-status rows in the message list, no attachment chips in historical user bubbles, no cosmetic-only i18n keys).

**Rationale:** User explicitly scoped follow-up work to release-ready items adapted for iOS HIG, avoiding behaviors that conflict with standard iOS sheet, keyboard, and list patterns.

---

### 2026-06-14 — Russian pluralization via xcstrings categories

**Decision:** All Russian count-dependent strings use String Catalog keys with `.one`/`.few`/`.many` suffixes resolved through `Bundle.appPluralizedString` and CLDR rules in `RecipeScalerCore`; different contexts use appropriate grammatical case (e.g. nominative for Discover counts, genitive after «не больше» in import errors).

**Rationale:** User reported incorrect forms like «3 рецептов» across Discover and other screens; suffix-based pluralization with context-specific copy matches Russian grammar and stays consistent between main app and Share Extension via `Shared.xcstrings`.

---