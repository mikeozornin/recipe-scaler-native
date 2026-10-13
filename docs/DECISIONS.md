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

### 2026-08-07 — Native primary protocol = `sync_step1`/`sync_step2`/`sync_update` (binary)

**Decision:** Native client uses the new Yjs Socket.IO protocol (`sync_step1` for state-vector diff load, `sync_update` for outbound edits) as the primary path, with raw `Data` binary frames for Yjs payloads. Server legacy events (`sync_request`, `load_document`, `document_loaded`) remain available as a fallback for old web/PWA builds; native no longer emits them on the primary path.

**Rationale:** Switching from full-state `load_document` + `sync_request` to state-vector-diff (`sync_step1` → `sync_step2`) cuts over-the-wire bytes on load to the missing ops only, and binary `Data` frames eliminate the ~3–4× inflation that JSON `[UInt8]` arrays suffered (notably on Socket.IO polling, where binary attachments were base64-encoded anyway). `YjsPayloadBytes.data(from:)` still accepts both `Data` and legacy number-array forms, so the migration is wire-compatible with any server build.

**Migration scope:** `SyncEventHandler.swift` (new `sync_step2` subscription + `onSyncStep2` callback), `YjsSyncService.swift` (`loadCollectionDocument`, `loadShoppingDocument`, recipe load path, recovery, reconnect — all switched to `emitSyncStep1`; push path is `emitSyncUpdate` → Socket.IO `sync_update`, `lastSyncedAt` dropped). `UpdateDebouncer` + `flushPendingEdits` on Done/`onDisappear`/`scenePhase` are unchanged and remain the client-side write debounce (no server-side write debounce by design — server writes immediately on receipt).

**Follow-ups (2026-08-08):** (1) `truncatedCollection` recovery mirrors web — drop in-memory + SQLite collection state and re-handshake with an empty state vector (plain `sync_step1` with a saturated SV no-ops). (2) Per-request ~5s `sync_step1` probe falls back once to legacy `load_document` without permanently pinning native to legacy.

---

### 2026-08-09 — Native Yjs work is session-scoped

**Decision:** Every native Yjs socket callback, delayed handshake/probe, serialized
`sync_update`, debounce batch, queue drain, acknowledgement, and recovery task carries
an immutable `(sessionId, userId, originating client)` context. The context is checked
after every suspension and immediately before persistence or emission. Document keys are
derived from the captured user, never from mutable current session state.

**Rationale:** Reconnect and account-switch races previously allowed delayed work from
one authenticated socket to resume against a replacement socket. Collection payloads
do not carry a user id, so checking only connection status could corrupt another
account's collection. Same-account reconnects preserve account-scoped local edits while
invalidating session-scoped wire operations.

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

**Superseded (2026-08-04):** Profile toggle shipped. APNs registration (`PushRegistrationService`) and silent widget wake (030) are in place; enabling the toggle requests UN permission when needed and always calls `registerForRemoteNotifications` so the device token is uploaded. Footer explains that pushes are also required for background widget and Live Activity updates.

### 2026-08-04 — Profile push toggle enabled

**Decision:** Show the Account preferences toggle «Notify when timer ends» (`account.timer-notifications.*`). On enable: request notification permission if `.notDetermined`, then register for remote notifications so the device token reaches `POST /api/push/apns-register`. Section footer documents that pushes are required for background timer widget and Live Activity updates.

**Rationale:** Device APNs + silent `content-available` are the primary path for timely widget refresh when the app is killed (030); LA cross-device updates also depend on APNs. Keeping the toggle hidden after paid developer + backend were ready blocked opt-in registration from Account.

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

**Superseded 2026-08-05:** Live Activities (044) + LA push v1 (058) shipped; paid account active. Production alert/silent push (023) and widget background (030 v2) are in scope now — see updated PAID-doc.

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

### 2026-06-12 — Timer Live Activities (spec 044)

**Decision:** One Live Activity per active timer on Lock Screen; system semantic colors (`primary` / `orange` / `red`); edge-to-edge progress overlay; pause/resume via `LiveActivityIntent` + App Group action queue; deep link tap opens recipe via `recipe-scaler://recipe/{id}`.

**Rationale:** Implements the milestone deferred before production APNs (see 2026-06-08). Per-timer activities chosen for v1 despite HIG preference for a single rotating activity; coordinator allows consolidating later.

---

### 2026-06-12 — Agent debug logging: sandbox NDJSON file, not localhost ingest on device

**Decision:** Agent/debug logs write to `Library/Application Support/debug-session.ndjson` on both simulator and physical device. Do not rely on `127.0.0.1` HTTP ingest from a physical iPhone.

**Rationale:** On device, localhost is the phone itself — Cursor ingest on the Mac is unreachable. Unified file + pull gives parity.

**Superseded (2026-06-16):** logging disabled-by-default and `AGENT_DEBUG_LOG_ENABLED` — см. решение ниже про `AppLog`.

---

### 2026-06-16 — Unified AppLog facade (spec 028)

**Decision:** Single `AppLog` facade for all app logging. DEBUG builds write NDJSON to `Library/Application Support/debug-session.ndjson` **by default** (no scheme env required). Opt-out: `AGENT_DEBUG_LOG_DISABLED=1`. All builds mirror to `os.Logger`. `AgentSyncDebugLog` / `DebugSessionNDJSONLog` / `CursorDebugIngestLog` remain as thin compatibility wrappers. Agent pulls logs via `scripts/pull-app-logs.sh`; user exports from Profile → Diagnostics on device (DEBUG only). Release: no file; Diagnostics section (sync status + log export) hidden in profile.

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

### 2026-08-27 — Assistant tool-status rows (spec 073)

**Decision:** Native assistant shows tool-call progress as separate status rows (web parity): processing shimmer + one row per `tool-start` NDJSON event. Supersedes 2026-06-14 deferral of web-style tool-status rows.

**Rationale:** Users could not see assistant working during tool calls; web already had visible Marker rows. Cross-platform contract: [`specs/073-assistant-tool-status`](../../specs/073-assistant-tool-status/spec.md) (monorepo root, sibling to native/web repos).

---

### 2026-06-14 — AI Assistant: iOS-native release scope

**Decision:** Ship assistant release minimum with iOS-native patterns only — voice via `AVAudioRecorder`, offline disabled composer, FAB inset above tab bar/timer panel — without blind web UI copy (no web-style tool-status rows in the message list, no attachment chips in historical user bubbles, no cosmetic-only i18n keys).

**Rationale:** User explicitly scoped follow-up work to release-ready items adapted for iOS HIG, avoiding behaviors that conflict with standard iOS sheet, keyboard, and list patterns.

---

### 2026-06-14 — Russian pluralization via xcstrings categories

**Decision:** All Russian count-dependent strings use String Catalog keys with `.one`/`.few`/`.many` suffixes resolved through `Bundle.appPluralizedString` and CLDR rules in `RecipeScalerCore`; different contexts use appropriate grammatical case (e.g. nominative for Discover counts, genitive after «не больше» in import errors).

**Rationale:** User reported incorrect forms like «3 рецептов» across Discover and other screens; suffix-based pluralization with context-specific copy matches Russian grammar and stays consistent between main app and Share Extension via `Shared.xcstrings`.

---

### 2026-06-15 — Collection pin grouped with leading swipe actions

**Decision:** In collection list rows, the **pin** action is part of the leading swipe / context group (alongside trash and folders), not the trailing group.

**Rationale:** Pin is conceptually organizational/destructive; grouping it with trash + folders matched the user's mental model of the leading action cluster (spec 026-collections US9).

---

### 2026-06-15 — Drop setLink UI and upload-from-URL from native scope

**Decision:** Remove the **setLink UI** from the native description editor (spec 018) and **upload-from-URL** (spec 016) — both cut from their specs entirely, not deferred.

**Rationale:** Link insertion was deemed unnecessary for native v1; upload-from-URL has a backend API but no UX need on iOS. Both removed from the corresponding `spec.md` files.

---

### 2026-06-15 — Search bar in the header for chats and recipe attachment picker

**Decision:** The assistant's chat-list search and the recipe-attachment picker search both live in the **header** with consistent placement; drop the «Чаты» title if needed to make room. Search is **not** auto-closed after use.

**Rationale:** Inconsistent placement (header in the picker, in-list in chats) felt wrong; user wanted header parity across both entry points and Telegram-style persistence.

---

### 2026-06-16 — Native export/import via NativeRecipeDraft, not ThirdPartyRecipeDraft

**Decision:** Build a separate Recipe Scaler v1.0–v1.4 export/import pipeline (spec 029) with a new `NativeRecipeDraft` type mirroring `RecipeData + CollectionEntry + RecipeFolder` 1:1, instead of reusing `ThirdPartyRecipeDraft`.

**Rationale:** `ThirdPartyRecipeDraft` is lossy — no `id`, `color`, `nutrition`, exact timestamps, or `folderIds` — so it cannot support lossless round-trip. Web parity with `v1.4-exporter.ts` / `v1.4-importer.ts` requires a richer draft; pipeline is fully offline-first through Y.Doc.

---

### 2026-06-16 — Recipe GUIDs are lowercase

**Decision:** Recipes created from the native app use **lowercase** UUIDs (matching web convention); uppercase GUIDs break deep-link parity.

**Rationale:** Web URLs and GUID storage assume lowercase; an uppercase native-generated GUID produced a non-matching deep link (`recipe-scaler://recipe/{id}`). Same rule was propagated into the spec.

---

### 2026-06-16 — Third-party import normalizes ingredients to typed fields (even at data loss)

**Decision:** Third-party imports (e.g. Crouton) normalize ingredients into the standard typed structure (name + typed unit + quantity), even if this loses the source's freeform unit text — never dumping "25 г" into a single untyped field.

**Rationale:** Crouton imports pushed the unit into the quantity field, producing un-editable ingredients that behaved differently from other recipes. User explicitly preferred uniformity over fidelity.

---

### 2026-06-16 — Single inline delete confirmation, web-style

**Decision:** Recipe / assistant delete uses **one** inline confirmation styled like the web app. The second, differently-styled confirmation component that was rendering alongside the inline one is fully removed (not just un-called); the guard against double-trigger stays.

**Rationale:** Two confirmation blocks rendered simultaneously, causing a flicker of a "second confirmation". Single inline component matches web parity.

---

### 2026-06-19 — Pin Swift Package dependencies (commit Package.resolved)

**Decision:** `RecipeScalerNative.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is committed to the repo to pin all Swift Package dependencies, matching web's lockfile practice.

**Rationale:** User explicitly requested dependency pinning after discovering Package.resolved was gitignored. Prevents surprise version bumps during CI or team checkout.

---

### 2026-06-19 — Typed ServerErrorCode enum replaces string prefix matching

**Decision:** Replace `switch errorString.hasPrefix("…")` patterns in `ServerError.swift` with a typed `ServerErrorCode` enum (`enum ServerErrorCode: String`) that maps known server error codes. Unknown codes fall through to a generic case; localization keys stay unchanged.

**Rationale:** String-prefix matching is fragile across localization changes and masks typos. A typed enum provides compile-time safety and makes the contract between server and client explicit (MIK-135 / review #52).

---

### 2026-06-19 — Drop ingredient unit canonicalization in Paprika/Crouton imports

**Decision:** Remove regex-based ingredient unit canonicalization (`tablespoon → ст.л.`, `cup → стакан`, etc.) from both Paprika and Crouton import parsers. Import ingredients as-is from the source file — "как пришло так и пришло". The standard typed ingredient structure (name + amount + unit) is still parsed; only unit-name rewriting is removed.

**Rationale:** Divergent normalization rules between Paprika and Crouton parsers produced inconsistent ingredient display (MIK-145 / review #62). User chose fidelity over normalization: regex rewriting added complexity without clear user benefit, and the original unit names are understandable as-is.

---

### 2026-06-19 — Linear MCP as primary bug tracker for code review findings

**Decision:** All findings from the system-wide code review document (`review-kilo-glm-5.2-recipe-scaler-native.md`) are migrated to Linear issues via `plugin-linear-linear` MCP, categorized by priority and tagged by area (e.g. `Architecture`, `Business Logic`, `Performance`, `Security`). The markdown review file remains as a reference index but issues are tracked and closed in Linear.

**Rationale:** User explicitly requested migration of even completed items into Linear for unified tracking. Linear provides better prioritization, assignment, and visibility than a static markdown file.

---

### 2026-06-20 — SwiftData ModelContainer graceful fallback to in-memory store

**Decision:** When SwiftData `ModelContainer` initialization fails (e.g. corrupted store, schema migration error), fall back to an in-memory store instead of crashing with `fatalError`. The app remains functional with a warning; data is not persisted but the user isn't locked out.

**Rationale:** `fatalError` on store init failure bricks the app with no recovery path (MIK-152 / review #68). In-memory fallback lets the user continue using the app while the underlying store issue can be diagnosed and fixed on next launch.

---

### 2026-06-20 — Per-recipe sync flags move from UserDefaults to SQLite

**Decision:** Per-recipe sync-state flags (currently stored as `UserDefaults` keys keyed by recipe ID) are migrated to the SQLite database as a proper table column or dedicated table, decoupled from `UserDefaults`.

**Rationale:** `UserDefaults` is designed for small, user-facing preferences, not per-entity state that grows with the number of recipes (MIK-128 / review #45). SQLite provides transactional safety, queryability, and avoids `UserDefaults` plist bloat as the recipe count grows.

---

### 2026-06-20 — Regex literal `try!` at static init → compile-once pattern

**Decision:** Replace `static let pattern = try! NSRegularExpression(pattern:..., options: [])` declarations (which force-unwrap regex compilation at static init time) with a lazy `static var` that throws only when accessed, or use `#/regex/#` literals (Swift 5.7+) where possible. The `try!` sites in `PaprikaRecipeParser.swift` and `CroutonRecipeParser.swift` are refactored.

**Rationale:** `try!` on regex literals crashes the entire app on launch if any regex pattern is malformed (MIK-143 / review #59). While regex literals are deterministic, the crash-on-launch cost is disproportionate. Compile-once + lazy access limits blast radius.

---

### 2026-06-20 — Socket.IO binary payloads: fix byte-per-int inflation

**Decision:** Socket.IO sync payloads that transmit raw Yjs binary updates now use the minimal byte encoding instead of the legacy one-byte-per-32bit-int representation that inflated payloads 4×. The fix targets the `SyncPayload` encoding layer shared by `YjsSyncService` and the Socket.IO transport.

**Rationale:** Each `Uint8Array` byte was packed as a 32-bit integer in JSON, inflating binary CRDT payloads by ~4× (MIK-100 / review #17). The user explicitly required that sync not break — the fix is isolated to the transport encoding layer, keeping the Yjs protocol unchanged.

---

### 2026-07-02 — Keep seed phrase after device-token migration

**Decision:** After migrating to device bearer tokens (spec 041), retain the user's seed phrase in secure storage; do not clear it as part of migration completion.

**Rationale:** The seed phrase is still required to show the user how to sign in on another device. Deleting it after token issuance would block that recovery path.

---

### 2026-07-03 — Default collections view is folder grid

**Decision:** New sessions default the collections screen to folder grid display instead of list mode. Users can still switch modes; only the initial/default preference changes.

**Rationale:** User explicitly asked to change the default from list to folders (“папочки”) for a more visual home screen.

---

### 2026-07-03 — Defer Mac/iPad layout (spec 046) on a branch

**Decision:** Pause spec 046 Mac/iPad layout work on a dedicated branch until iPad simulator navigation and hit-testing issues are resolved; do not ship partial iPad layout on `master` yet.

**Rationale:** iPad simulator showed a white screen and non-clickable UI; user chose to defer polish rather than block `master` with unfinished adaptive shell work.

**Update (2026-10-12):** Resolved for spec 081. The iPad shell spike (T005/T006, iPadOS 26.3 simulator) found no white screen: `TabView(.sidebarAdaptable)` with a dynamic `TabSection`, `.sectionActions` and `.tabViewSidebarBottomBar` renders and every row is clickable. The non-clickable / mis-inset toolbars it did find came from a TabView-level `.inspector` and a `NavigationSplitView` inside a `Tab`; see the 2026-10-12 entries below.

---

### 2026-07-03 — Ingredient illustrations: no iPad in initial native scope

**Decision:** Ingredient illustration parity with web ships for iPhone first; iPad-specific layout for the picker/catalog is out of scope for the initial implementation (“ipad не делаем”).

**Rationale:** User narrowed scope to match web behavior on phone; iPad adaptive UI deferred with spec 046.

---

### 2026-07-03 — Illustration assets: WebP from transparent PNG

**Decision:** Bundle ingredient and empty-state illustrations as WebP derived from transparent PNG sources; do not ship JPEGs with opaque white backgrounds.

**Rationale:** User required dark-mode-safe artwork; white-filled JPEG backgrounds looked wrong in dark UI. WebP from transparent PNG preserves alpha and reduces bundle size vs raw PNG.

---

### 2026-07-04 — Offline outbox: dequeue only on `sync_confirmed`

**Decision:** `offline_sync_queue` rows are removed only after the server acknowledges with `sync_confirmed`, not immediately after a successful Socket.IO emit. Legacy README plans 003/004 that implied post-emit deletion are superseded for runtime behavior.

**Rationale:** Code review flagged data loss if the app crashes between emit and ack. User chose the reliable variant (“корректный и надёжный”) over faster dequeue, aligning with durable offline-first sync.

---

### 2026-07-04 — Process: positive invariants + downstream consumers in plans

**Decision:** Every feature `plan.md` (Spec Kit) must include two mandatory sections: **Downstream consumers** (all readers of mutated state, including cross-process ones) and **Positive invariants** (one observable behavioural assertion per effect). Template at `specs/_template/plan.md`. Principles codified in `docs/TESTING.md`. Supporting tooling: `scripts/verify-ui-smoke.sh` (cross-screen smoke), `scripts/lint-i18n.sh` (hardcoded UI literal detector).

**Rationale:** Recurring regression class (most notably MIK-187 widget freeze, 22 Jun 2026): a function doing two observable effects had negative tests only. Removing the "extra" effect (widget snapshot) passed all tests because no assertion required it. ~200 i18n corrections and ~400 UI-layout corrections over 30 days of transcripts indicated the existing per-feature verify-*.sh scripts leave gaps between features. New tooling closes launch/crash/hang/empty-flicker detection at the cross-screen level, and the i18n lint widens the existing `verify-translations.sh` scope. Plan-level rule shifts the burden of identifying "what could break downstream" from the reviewer to the author, before code is written.

---
### 2026-10-10 — Local yrs edits sync as deltas, not full state

**Decision:** `DocumentManager.persistAndDeliver` / `deliverPendingLocalUpdate` forward the yrs transaction deltas (`consumePendingLocalUpdateParts`, unmerged; the debouncer merges them with `Y.mergeUpdates`) instead of `encodeStateAsUpdate` of the whole doc. The SQLite snapshot stays synchronous per edit; `sendDebouncedUpdate` no longer re-encodes. Remote and description-editor applies no longer clear or capture pending local deltas. Collection: live `sync_update`s without `sync_confirmed` trigger one full-state push after the next collection handshake.

**Rationale:** Perf review 2026-10-09 №1: each pin/rename cost O(document) (≈400 KB collection) through the >32 KB emit queue (~1.3 s) and stored full copies in `offline_sync_queue`. The server (`sync_update`/`sync_request`) merges with `Y.applyUpdate`, and the web client already sends deltas. The 2026-06-12 switch to full state was a workaround for the yrs empty-doc merge no-op, which is now solved by `YjsMergeHelper`. Recipe docs keep the unsynced flag + wire-snapshot reconnect push. Collection has no such flag, so the unconfirmed-emit counter replaces the old "next full-state edit heals the gap" behaviour.

**Follow-up (review №2, same day):** `yjs-merge-helper.html` had never worked: it called a global `Y`, but `yjs.bundle.js` only exposes `YjsBundle.Y`, so every `mergeUpdates` / `encodeFullState` threw and callers silently fell back via `try?`. With full-state queue entries that was harmless; with deltas the offline drain's `parts.last` fallback would drop all but the last edit. Fixed the global, moved the bridge to base64 strings via `callAsyncJavaScript` arguments (no per-byte `NSNumber` + JSON on the main thread; 400 KB `encodeFullState` ≈ 10 ms on simulator), log `yjs_merge_helper_eval_failed`, and made the drain fall back to the local yrs snapshot (holds every queued edit) instead of `parts.last`.

The description editor bridge (`description-editor-bridge.js` ↔ `DescriptionEditorWebView` / `DescriptionEditorBridge`) uses the same base64 encoding for `init`, `applyUpdate`, `update` and `syncState`; Swift still accepts number arrays.

**Review №2, items 3–4:** `CollectionEntry` precomputes `displayName` / `leadingEmoji` once (sorting 500 entries 42 → 6 ms on simulator), the search path reuses the already-sorted `collectionIndex.live`, and the index is rebuilt only when entries change. Live Activity: `TimerLiveActivityCoordinator` skips non-user-action updates whose content equals `activity.content.state` (ignoring `syncedAt`) and whose clock-derived render (accent, AOD compact text) is unchanged since our last push — the per-tick calls stay, so APNs-driven changes and failed updates still converge. `TimerManager` drops to a 30 s loop once every running timer has completed instead of ticking every second; the LA thumbnail is downscaled to 72 px off the main actor and cached by source mtime.

**Review №2, appendix (validated by failing-then-passing tests):** `NSRegularExpression` ranges are UTF-16, so `RecipeDescriptionParser` maps them back with `Range(_:in:)` (static regexes, anchored inline match) — `String.index(offsetBy:)` dropped text after emoji and crashed on the last block. `RecipeSearchUtils.buildNormalizedWithMap` keeps one map entry per UTF-16 unit of the normalized string (highlight after emoji was shifted and crashed at the end of a line; the description snippet window drifted). `DocumentManager` does not persist empty docs (`[0, 0]`, e.g. a recipe peeked for search before download) and `existingSnapshotKeys` ignores legacy `x'0000'` rows, otherwise the recipe was never downloaded. The unit-test bundle registers `NoExternalNetworkURLProtocol` via `NSPrincipalClass` (`TestBundleSetup`): the test host shares the app keychain, and timer/system-banner tests were calling `/api/push/schedule|cancel`, `apns-register-liveactivity` and banner dismiss for the signed-in user.

**Review №2, appendix follow-ups (same validation):** Reconnect (`refreshWireSnapshotsForRecipes`) filters candidates by `hasUnsyncedLocalChanges` before reading any yrs or wire snapshot, and the description export check reads `offline_sync_queue` once, not once per recipe (30 synced recipes: 30 snapshot reads → 0, 30 queue queries → 1). Offline description-editor updates no longer write a full yrs snapshot each: the queue row is the durable copy (replayed by `loadLocalSnapshots`), the snapshot stays on the 500 ms debounce (10 updates: 10 writes → ≤ 1). List search: `RecipeSearchIndex` carries its normalized fields, built once in `DocumentManager` and cached by state vector; `RecipeListSearchStore` re-peeks loaded indexes after the debounce, so edits that never touch the collection entry (description editor, remote) are found (300 warm re-peeks ≈ 21 ms, off the keystroke path). Description matching uses `.literal` (the non-literal `NSString` search was 18 of 24 ms), so Cyrillic is NFC-folded before comparison; Latin uses NFKD as the search rule says (was NFD: `ﬁ` and full-width forms did not match). 300 loaded indexes per keystroke: 297 → 9.5 ms (Debug, simulator). `IngredientIllustrationCatalog` memoizes name-matcher results by trimmed name: shopping rows re-match every label on each render, 41 rows 102 → 0.02 ms.

---

### 2026-10-12 — iPad recipes columns (spec 081 Р5): two NavigationStacks in an HStack (variant B)

**Decision:** On iPad in a regular-width window the Recipes section is an `HStack` of two `NavigationStack`s (`IPadRecipesSplitView`): list column 320 pt + 1 pt divider + recipe panel. It does not use `NavigationSplitView` (variant A). The "Recipe list" button (`sidebar.left`), the list sliding over the recipe (`.overlay` with a 0.25 dim) and the column styling are our own code. The list's search state lives outside the list's `NavigationStack`, so a query survives inline ↔ hidden ↔ overlay. Visually the layout matches `specs/081-ipad-adaptation/layout.md`.

**Rationale:** Spike S4 (iPadOS 26.3 simulator, iPad 11″ portrait), evidence in `tmp/ipad-research/spike-verdicts.md` and screenshots `s2-02`, `s4-01`…`s4-07`.
- Variant A breaks on the main scenario. After the sidebar is shown and hidden (button or programmatic), the split's column nav bars keep a stale top inset and slide under the floating tab bar (y=46 instead of 90), so "…" and ✦ overlap Profile and Assistant. Only a tab switch fixes it.
- `setNeedsLayout`, bouncing the tab bar and `.id(tabBarPlacement)` on the split did not help, and `additionalSafeAreaInsets` overshoots (y=122). The cause is a nested `UISplitViewController` inside `UITabBarController`.
- Variant B keeps correct toolbars before and after sidebar toggles, including with the assistant panel open. STOP 3 ("both variants break") was not triggered.
- The cost of B is a custom list button, a custom overlay and manual column styling.

---

### 2026-10-12 — iPad assistant (spec 081 Р7): own trailing panel, not TabView `.inspector`

**Decision:**
- In a regular-width iPad window the assistant is our own trailing panel, 340 pt wide: `HStack { TabView │ Divider │ AssistantSheet(presentation: .inspector) }`, shown and hidden by the single `showAssistant`. In compact width and on iPhone it stays the existing sheet.
- Assistant session state moves out of `AssistantSheet`'s `@State` into a shared `@Observable` `AssistantSessionModel` owned by `AppContainer` and passed explicitly. That state covers messages, draft input, attachments, thread and the stream/bootstrap tasks.
- The model cancels its tasks on explicit close, on session-epoch change and on logout, not on view `onDisappear`.
- The timer popover is lifted from inside `tabViewBottomAccessory` to the shell and anchored to the accessory's measured frame.

**Rationale:** Spike S5/S6, evidence in `tmp/ipad-research/spike-verdicts.md`.
- A TabView-level `.inspector` set the top safe area to 0 on every tab except the first, and on collection tabs, pushing toolbars under the floating tab bar. That is STOP 2, bisected with flags (`s1-05` vs `s1-20`).
- A per-tab `.inspector` keeps the insets but rebuilds the assistant on every tab switch and loses the draft (`s5-03`–`s5-05`).
- The custom panel keeps the insets and survives tab switches (`s5-06`, `s5-07`); compact shows the sheet (`s5-08`).
- Panel and sheet are different view instances, so without the shared model a size-class change would drop the draft and cancel the streaming reply.
- `.popover` inside the bottom accessory never appears. Lifted to the shell it works, including in sidebar mode (`s6-02`, `s6-03`, `s6-06`). The accessory exists in sidebar mode, so no custom capsule is needed.

---

### 2026-10-12 — iPad: single resizable window, multiple windows out of scope (spec 081 STOP 5)

**Decision:** Spec 081 ships one window. It supports Split View, Slide Over and Stage Manager resizing. `UIApplicationSupportsMultipleScenes` is not added and there is no "New Window". Multiple windows need their own spec.

**Rationale:** Spike S7 found it expensive.
- There is a single `WindowGroup` (`RecipeScalerNativeApp.swift:176`) and one shared `AppContainer` with a single `shellCoordinator` (`AppContainer.swift:65`), so tab selection, navigation paths and `showAssistant` would be shared across windows.
- `DeepLinkRouter.shared` has one `pending` slot (`DeepLinkRouter.swift:57`, `:99`) and is called from App Intents and `TimerManager`, with no way to pick a target window.
- More process-wide singletons would need per-scene review: `AssistantRecipeContext`, `TimerManager` panel flags, `ReleaseNotesStore`, `ClipboardImportStore`, `OfflineBannerGate`, `RecipeFileImportCoordinator`.
- A future spec would need a per-scene `AppShellCoordinator`, a scene-aware router and a review of each singleton. The user's Q4 answer was "only if cheap".

---

### 2026-10-12 — Renew SnapshotTests quarantine to 2026-11-12

**Decision:** Keep `RecipeScalerNativeTests/SnapshotTests` quarantined in `scripts/test-quarantine.json` and move its expiry from 2026-10-01 to 2026-11-12. Owner, exit criteria and removal condition are unchanged: an AppContainer-based test host injected into the `#Preview` paths, plus 3 consecutive passes.

**Rationale:** The entry had expired, which `scripts/check-test-quarantine.py` treats as red. On 2026-10-12 the suite was run twice on the iPhone simulator (`build-for-testing`, then `test-without-building -only-testing:RecipeScalerNativeTests/SnapshotTests`). Both runs failed the same way, with `TEST EXECUTE FAILED` and the test host crashing before any test completed:
- `testAuthView` — `No Observable object of type AuthService found`;
- `testRecipeListView` — `No Observable object of type ReleaseNotesStore found`.

The suite also has no recorded reference snapshots (`isRecording = false`, no committed `__Snapshots__` images), so even with environment objects it would fail on the missing references. Fixing it means app-side test-host / test code changes plus recording references, which is outside the iPad-spike docs task. Removing the entry would make the fast suite red, and deleting the tests would drop the only snapshot coverage stub. So the entry is renewed with an updated reason.

---

### 2026-10-12 — iPad sidebar: an empty «Коллекции» section keeps one hidden child tab (spec 081 US1)

**Decision:** The sidebar's «Коллекции» `TabSection` always contains one extra child tab, `IPadShellItem.newCollection`, with `.defaultVisibility(.hidden, for: .sidebar)`. It is never selected; it only keeps the section alive. UI tests find the section's «+» action and the new-collection alert's text field by accessibility id OR by label.

**Rationale:** On iPadOS 26.3 a `TabSection` with no child tabs is dropped together with its header and its `.sectionActions`, so a user without collections had no «+» to create the first one. A hidden child keeps the section (and the action) on screen without showing a row. The same system build drops `accessibilityIdentifier` on section actions and on alert `TextField`s, so id-only queries fail; matching by label as a fallback keeps the tests stable without inventing a custom control.

---

### 2026-10-12 — UI tests add shopping items through the app, not via REST seeding

**Decision:** iPad UI tests that need shopping-list items create them through the app (recipe → «В список покупок», or the shopping list's own add field). They do not seed the list over REST.

**Rationale:** The shopping list is a Yjs document synced over the WebSocket; the backend has no REST write endpoint for list items. Writing a raw Yjs update from the test would duplicate the sync client in test code. Going through the app exercises the real path and needs no backend changes.

---

### 2026-10-12 — iPad profile form sheet survives narrowing to compact

**Decision:** While the «Профиль» form sheet is up, tapping «Профиль» again keeps the sheet and the previously selected section, in any layout mode. `IPadProfileSheetPolicy.resolve(…, isSheetPresented:)` makes this decision; `AppShellCoordinator` passes `isProfileSheetPresented`. There is never a second `AccountView` (one in the sheet and one as a tab page).

**Rationale:** UIKit keeps a presented form sheet when the window narrows from regular to compact (Split View, Stage Manager). Without the flag, a compact-width tap on «Профиль» switched the tab to the profile page while the sheet was still up, so two `AccountView`s ran at once and fought over the same state.

---

### 2026-10-12 — verify-ipad-layout.sh: discover states only with an explicit profile slug

**Decision:** `scripts/verify-ipad-layout.sh` captures `discover-feed` and `discover-author` only when `IPAD_VERIFY_DISCOVER_PROFILE=<slug>` is set. There is no default slug; without it the script skips both states and prints why.

**Rationale:** The discover screens show other people's public data. A hard-coded real profile would put a real person's recipes into committed or shared screenshots by default. An explicit, validated slug (`[A-Za-z0-9._-]`) makes that a conscious choice.

---

### 2026-10-12 — DEBUG `-IPadSidebarShown=1` forces the sidebar visible in portrait

**Decision:** DEBUG builds accept `-IPadSidebarShown=1`: at `.padRegular` the app shows the sidebar shortly after launch, also in portrait where the system default is hidden. `-IPadSidebarHidden=1` wins when both are set. Release builds ignore both.

**Rationale:** Layout verification (`verify-ipad-layout.sh`, `#recipes-sidebar` and the threshold matrix) needs the portrait-with-sidebar state without a tap sequence. The flag goes through the same `IPadSidebarControl.setSidebarHidden` path as the user's button, so the captured layout is the real one.

---

### 2026-10-12 — iPad: one assistant entry on screen, ✦ only while the sidebar is shown (spec 081 FR-021)

**Decision:** On `.padRegular` the toolbar ✦ (`IPadAssistantToolbarButton`) on «Покупки», «Подборки» and the recipe panel shows only while the tab bar is the sidebar. In the top tab bar the pinned «Ассистент» tab is the only entry, so there is no toolbar ✦ anywhere. A compact window and the iPadOS 17.0–26.1 system tab bar have no ✦, as on the iPhone. `IPadAdaptiveTabView` decides once from `\.tabBarPlacement == .sidebar` (`IPadLayoutPolicy.showsAssistantToolbarButton`) and passes a plain `Bool` to the tab roots; toolbars never read the placement or an `@Observable` from the environment.

**Rationale:** With the sidebar hidden the top bar already shows the pinned «Ассистент» tab, so a toolbar ✦ put two assistant buttons on screen at once. The sidebar hides «Профиль» and «Ассистент», so there ✦ is the only way in. One shell-level value keeps all three screens consistent and avoids the iOS 26 fallback-environment trap in toolbar content. The recipe toolbar also gets shorter in the top bar, where its row is shared with the tab bar.

---

### 2026-10-12 — iPad: the recipe toolbar beside the floating tab bar (spec 081 T026, variant B)

**Decision:** When the Recipes split's top edge is in the row of the floating top tab bar (`IPadLayoutPolicy.toolbarSharesTabBarRow`, split top < `IPadLayoutMetrics.separateToolbarRowMinTop`), the recipe toolbar uses `IPadDetailToolbarStyle.padBesideTabBar` below a 1100 pt content width: one capsule «…», «Не гасить экран», pencil; like the narrow toolbar (FR-013) it has no «Поделиться». From 1100 pt (landscape) the usual wide/narrow thresholds apply. The split measures its top edge with the `GeometryReader` it already has for the content width.

**Rationale:** iPadOS 26.3 puts a page's navigation bar into the tab bar row, as it does on «Покупки». The two `NavigationStack`s of variant B get their own row under the tab bar on a fresh launch (top 96) and move into the tab bar row after the scene reactivates or the sidebar toggles (top 32). In portrait only about 150 pt is left beside the tab bar, so the wide toolbar overflowed into the system «⋯», and the shared phone group (a custom view in one bar item) vanished from it. Padding or `safeAreaPadding` moved the bar down but UIKit kept the overflow, and `additionalSafeAreaInsets` (spike) overshot. Fitting the items keeps every action visible in both states without fighting UIKit.

---

### 2026-10-12 — iPad: list toggle + overlay replaced by a Notes-style expand button (spec 081 US2, user decision)

**Decision:** On `.padRegular` the Recipes section works like Apple Notes. The sidebar is only the app menu (sections and collections). The list column always stands beside the recipe while the recipe keeps at least 320 pt: half of the content in portrait (content taller than wide), a third in landscape, never under 320 pt (`IPadLayoutPolicy.listColumnWidth`); with the sidebar beside the content the rule applies to the rest of the window. Below that the section is the phone stack. «Развернуть» (`arrow.up.left.and.arrow.down.right`) at the leading edge of the recipe toolbar gives the recipe the whole section and hides a sidebar that stood beside the content (`IPadSidebarControl`); «Свернуть» (`arrow.down.right.and.arrow.up.left`) brings the list and that sidebar back. The expanded flag lives in `AppShellCoordinator` for the session only. The «Список рецептов» button, the slide-over list and its dimming are deleted, and `minDetailWithList` drops from 560 to 320. The recipe's own two-column rule (panel ≥ 720 pt) and its draggable divider are unchanged.

**Rationale:** User decision 2026-10-12: follow Apple Notes. The list is there whenever it fits and one button gives the recipe the whole section, instead of our own list toggle next to the system sidebar button and a list sliding over the recipe. The proportions (½ portrait, ⅓ landscape) are the owner's; a portrait half keeps the recipe in one column, landscape and expanded give it two. Expanded, the list column stays in the hierarchy off the leading edge (transparent, no hit testing, hidden from accessibility): removing it lets iPadOS 26.3 move the recipe bar into the tab bar row and keep it there after collapse.

---

### 2026-10-12 — iPad: «Развернуть» restores only the sidebar it hid (spec 081 US2)

**Decision:** `AppShellCoordinator` owns the expand state. `setRecipeDetailExpanded` hides the sidebar only when it stands beside the content and remembers that in `sidebarHiddenByRecipeExpand`; the decisions are pure functions in `IPadLayoutPolicy`. The recipe collapses when the window narrows to the phone stack (push) or to compact. The remembered sidebar comes back only on the Recipes tab in a regular window: a collapse elsewhere (an empty collection opened from the sidebar, compact) defers the restore until the user returns there. If the user shows the sidebar while expanded, the flag clears and «Свернуть» leaves it alone. Sign-out shows a sidebar that expand hid before it clears the flags. Expanded, the list column's `NavigationStack` stays in the hierarchy (the toolbar workaround) but is emptied, so no rows, «+» or search field remain for XCUITest, VoiceOver or Full Keyboard Access.

**Rationale:** Review of the Notes-style expand found that the sidebar could stay hidden after the window narrowed or after sign-out, and that it could pop open over another tab. Restoring only what we hid, and only where it was hidden, never fights the user. An empty stack keeps the toolbar fix and removes the invisible but reachable list.

---

### 2026-10-12 — iPad: the assistant panel on Recipes always hides the list column (spec 081 US3, user decision)

**Decision:** When the assistant panel opens on the Recipes tab, the list column is always hidden at any window width: the screen shows the recipe and the chat. Closing the assistant brings the list back under the usual FR-011 rules, keeping the open recipe and the selected row. Recorded in spec.md (US3, FR-022) and layout.md (`#assistant/chat`); implemented with US3.

**Rationale:** User decision 2026-10-12. Recipe plus chat is the working pair while talking to the assistant. A list squeezed beside both would leave the recipe in one narrow column.

---

### 2026-10-13 — iPad: one assistant session for the panel and the sheet (spec 081 T032a, T032)

**Decision:** The assistant chat state (thread, messages, draft, attachments, stream, bootstrap and external-send tasks) lives in `AssistantSessionModel`, owned by `AppContainer` and passed to `AssistantSheet(session:)` explicitly. The shell drives its lifecycle: `beginPresentation` on open, `close()` when `showAssistant` turns false, `resetForLogout` from the composition root, and a session epoch change drops a stale stream. `AssistantSheet` no longer cancels anything in `onDisappear`. On `.padRegular` the assistant is a 340 pt panel in an `HStack` beside the `TabView`; elsewhere it is the phone sheet; one `showAssistant` drives both. The sheet's binding is `showAssistant && layoutMode != .padRegular`, and its setter ignores the dismissal that SwiftUI sends when the sheet yields to the panel (an `@State` mirror of the layout mode, `assistantShowsAsPanel`). Closing the assistant also drops the pending external request.

**Rationale:** Panel and sheet are different view instances, so view-owned state lost the draft and cut the stream on every size class change (spike S5). A model at the container survives the swap and keeps the iPhone behavior; the only iPhone change is that the draft now survives closing and reopening the sheet (plan.md Р7). SwiftUI dismisses a sheet through the binding closure it was presented with, which still saw the compact layout; without the guard it set `showAssistant = false` and the panel never appeared. A stale external request blocked the next tab open (PI-5).

---

### 2026-10-13 — iPad: toggling the assistant panel (spec 081 T034, FR-021, FR-022)

**Decision:** In a wide window the pinned «Ассистент» tab and ✦ open and close the panel without changing the selected tab. ✦ on «Покупки» and «Подборки» opens it with a new chat and keeps the typed draft; the tab and the recipe ✦ restore a chat opened in the last 60 s, as on the iPhone. On «Рецепты» an open panel hides the list column; whether the section is the split or the phone stack is decided on the width without the panel (`IPadLayoutPolicy`, `assistantPanelOpen`; see «the assistant panel keeps the Recipes section's mode» below), and «Развернуть» is hidden while the panel is open, with the expanded state restored on close. A tab tap in the same update as an external request does not toggle the panel shut, and an external request reaching an open assistant goes to the session directly, deduplicated by request id.

**Rationale:** The panel is a companion to the current screen, so opening it must not navigate. «Покупки» and «Подборки» have no recipe in context, so ✦ there starts a new chat (T034). Deciding split vs stack without the panel means opening or closing it never swaps the recipe view (scroll position, cooking state) and never collapses an expanded recipe. The PI-5 rules stop «Купить во Вкусвилле» from opening and immediately closing the panel or sending twice.

---

### 2026-10-13 — iPad: assistant panel chrome (spec 081 T033)

**Decision:** The panel bar shows «Ассистент» as a leading toolbar item in the display face at 20 pt (the prototype's `.insp-bar h3`), fixed at 120 pt (`IPadLayoutMetrics.inspectorTitleWidth`), with the system title removed. On the trailing side: a [history, new chat] group, a `ToolbarSpacer` and ×. History opens as an `.adaptivePopover` (`historyPopoverWidth` × `historyPopoverMaxHeight`, 316 × 420) with the `AssistantThreadListSheet` content. The panel has no accessibility id of its own; UI tests find it by its bar with × (`ipadAssistantInspectorCloseButton`). The phone sheet keeps its large title and bar.

**Rationale:** The system inline title shared the 340 pt bar row with three buttons and truncated to «Асси…». Any title wider than 120 pt pushed × into the system «More» overflow. `root_content` replaces the identifiers of top-level elements, so a panel id never reached XCUITest.

---

### 2026-10-13 — iPad: the system folds the sidebar beside the assistant panel (spec 081 T034, layout.md deviation 9)

**Decision:** We accept the iPadOS 26 behavior: when the `TabView` narrows beside the panel in landscape (11″: 1210 → 869 pt), the system folds the sidebar into the top tab bar and restores it when the panel closes. While folded there is no toolbar ✦, so the pinned «Ассистент» tab is the way in and out (consistent with FR-021). We do not hide or force the sidebar ourselves. The matrix row «Альбомная · весь · сайдбар да · инспектор да» therefore does not occur on the 11″; T049 confirms 13″ and the ⅔ window.

**Rationale:** The result matches the prototype, where the assistant always hides the sidebar, and it needs no code. Keeping the sidebar through `IPadSidebarControl` would leave the recipe about 590 pt wide in one column, squeezed between the sidebar and the panel.

---

### 2026-10-13 — DEBUG `-DebugCompactInPortrait=1` for size class switch tests (spec 081 T035)

**Decision:** A DEBUG launch argument makes the root a compact ½ window (402 pt, pinned to the leading edge) in portrait and leaves landscape regular, so a rotation is a runtime size class change. It lives in `DebugWindowWidthModifier` beside `-DebugWindowWidth` and compiles to nothing in Release. `IPadAssistantSpec.testSizeClassSwitchKeepsChat` uses it for panel → sheet → panel.

**Rationale:** Split View and Stage Manager cannot be automated on the simulator, and a fixed `-DebugWindowWidth` cannot change during a test. Caveat: the sheet is still presented by the real full-width window, so under this argument it looks like a centered page sheet, not a sheet in a ½ window. The test checks the chat and the draft, not the sheet's geometry.

---

### 2026-10-13 — iPad: hands-free stays disarmed while the assistant panel is open (spec 081 T034, interim)

**Decision:** For now the shell sets `assistantRecipeContext.isAssistantSheetOpen = showAssistant` for the panel too, so awake-scroll and hands-free control on the recipe disarm while the panel is open, as they do under the phone sheet. T036 (US4) revisits this for the panel, where the recipe stays visible.

**Rationale:** The flag also keeps the recipe context for the assistant when the recipe view disappears behind the sheet. Splitting «assistant open» from «recipe covered» touches the cooking strip and hands-free work that T036 owns, so US3 keeps the existing behavior rather than half-change it.

**Superseded** by «iPad: hands-free and keep-awake keep working beside the assistant panel» (T036, below).

---

### 2026-10-13 — iPad: the profile tab is `person.fill` in the top tab bar (spec 081, owner decision)

**Decision:** The iPad top tab bar names `person.fill` for «Профиль» (`AppTabBarLabel(tab:systemImage:)`, plus a `.fill` symbol variant). `AppTab.tabBarSymbol` and the iPhone bottom bar are unchanged.

**Rationale:** Same rule as 2026-06-02 (tab bar uses fill symbols and tint only). The iPhone bottom bar fills the symbol by itself; the iPadOS 26 top tab bar draws it as named, so the profile glyph looked hollow next to the filled ones.

---

### 2026-10-13 — iPad: the keyboard does not change the list column in portrait (spec 081)

**Decision:** The Recipes split reads the orientation from its size without the keyboard: a background sized with `.ignoresSafeArea(.keyboard)` gives `contentHeightIgnoringKeyboard` to `IPadLayoutPolicy.listColumnWidth`, and a stale measurement from before a rotation is ignored by its width. The columns themselves still avoid the keyboard. The DEBUG `-DebugCompactInPortrait` harness uses the same rule.

**Rationale:** The split's `GeometryReader` shrinks with the software keyboard: portrait 834 × 1100 became 834 × 700, was read as landscape, and the list column jumped from half (417 pt) to a third (320 pt) as soon as the search field got focus. `IPadRecipesSpec.testKeyboardKeepsTheSplit` covers it.

---

### 2026-10-13 — iPad: recipe columns without a draggable divider; the nutrition header wraps (spec 081 FR-012a, owner decision, supersedes Q5)

**Decision:** The two-column recipe has a fixed left column, `IPadLayoutPolicy.detailLeftWidth(detailWidth:) = min(400, panel − 1 − 320)`, so 400 pt and 399 pt at the 720 pt threshold, and a static 1 pt line between the columns. The drag gesture, the handle, the VoiceOver adjustable element, the `ipad.recipe.columnDivider*` strings, the `ipadRecipeColumnDivider` identifier and the persisted width are removed. The `UserDefaults` key `ipad.recipeDetailLeftColumnWidth`, already written on test devices, is no longer read; a leftover value is harmless. In `RecipeNutritionBlockView` the «КБЖУ на» row is a `ViewThatFits(in: .horizontal)`: the title and the basis selector on one line when it fits, otherwise the selector under the title.

**Rationale:** The divider is removed by the owner's decision of 2026-10-13. While checking the narrowest two-column width we found the cause of a column «shifted left» and clipped: the basis selector (`UISegmentedControl` with explicit segment widths) never gets narrower than its titles, so the row needs 390.5 pt in en and 374 pt in ru, and a vertical `ScrollView` whose content is wider than its frame grows and re-centers it. At 399/400 pt the row fits in both languages, so the iPad looks as before; the wrap keeps a narrower column correct. iPhone 17 Pro (402 pt) is unchanged in both languages, and ru is unchanged on every iPhone from 374 pt. In en at 375 pt (SE) and 390 pt (16e, 13, 14) the selector now sits under the title; before, the row overflowed there by 15.5 pt and 0.5 pt. A custom `Layout` that would tolerate 1 pt cannot delegate to `HStackLayout` / `VStackLayout` (their layout methods are not public API). `RecipeNutritionHeaderLayoutTests` covers en and ru at 320–402 pt.

---

### 2026-10-13 — Logout and account switch close the assistant and clear its recipe context (spec 081 US3 review)

**Decision:** `AppContainer.resetAssistantForLogout()` resets the chat session and `AssistantRecipeContext` together (`isAssistantSheetOpen`, `visibleRecipeId`). Both `stopForLogout()` and an account switch inside `bootstrap(userId:)` (`resetForAccountSwitch()`) call it. When `assistantSessionEpoch` changes, the shell closes an open sheet or panel, as it does with the profile and import sheets. The sheet's `onDismiss` now skips only the hand-over to the panel (`showAssistant && assistantShowsAsPanel`). A sheet torn down with the shell therefore counts as closed. `AssistantSessionModel.teardownForSessionInvalidation()` does the same reset as `resetForLogout()`. That reset also cancels the first bootstrap and the history refresh and drops a pending shake request.

**Rationale:** Before this, only the shell wrote the flag: its `onChange(of: showAssistant)` and the sheet's `onDismiss`. If the user logged out with the assistant open, the shell went away with `showAssistant` still true. The `guard !showAssistant` in `onDismiss` then skipped the reset, so the flag stayed true for the next account. While it is set, a recipe screen keeps its context and screen-awake mode on disappear and keeps awake-scroll disarmed (`YDocRecipeDetailView`). The old teardown also missed `initialBootstrapTask`, `threadsRefreshTask` and `pendingShakeRequest`. As a result, a dead session's history list or voice-start shake could land in the next one. The reset sits in one helper, so splitting «assistant open» from «recipe covered» later (T036) adds one line there.

---

### 2026-10-13 — iPad: the assistant panel keeps the Recipes section's mode (spec 081 T034, US3 review)

**Decision:** While the panel is open, `IPadLayoutPolicy.resolve(…, assistantPanelOpen:recipeOpen:)` chooses split or phone stack on the width without the panel, whether or not a recipe is open. That is the same mode as with the panel closed. Next to an open recipe the list column hides (FR-022). Without a recipe the list stays, because the split normally keeps one open (`repairSelection`); that happens only with an empty collection. «Развернуть» is hidden for as long as the panel is open.

**Rationale:** Before, the flag was `assistantBesideRecipe` (panel open and a recipe open). With the panel open and no recipe, the section decided on the narrowed width. In portrait on 11″ that is 493 pt, so it showed the phone stack, and picking a recipe switched it to the split: the list vanished and the recipe view was rebuilt. With one mode for the whole time the panel is open, picking a recipe only hides the list. `IPadLayoutPolicyTests.testAssistantPanelKeepsOneModeWithOrWithoutARecipe` covers 11″ portrait and landscape (with and without the sidebar), 13″ landscape and a 776 pt window with the sidebar.

---

### 2026-10-13 — iPad: hands-free and keep-awake keep working beside the assistant panel (spec 081 T036, US3 review M2 and L1, supersedes the interim T034 entry)

**Decision:** `AssistantRecipeContext` tells «the assistant is open» from «the assistant covers the recipe». `isAssistantOpen` is any open assistant; `coversRecipe` is only the phone sheet (iPhone, a compact iPad window); `isBesideRecipe` is the iPad panel. The shell reports `assistantDidOpen(asPanel:)`, `assistantDidMove(asPanel:)` on a size class change and `assistantDidClose()`. Awake-scroll, hands-free and the recipe's `onDisappear` read `coversRecipe`, so beside the panel the recipe works as it does without one: the cooking strip stays, hands-free stays armed, and leaving the recipe drops its context and keep-awake. When the panel is open and the user switches to «Покупки» or «Подборки», the shell calls `releaseRecipe(hiddenBy:)`: the composer stops offering the hidden recipe and `ScreenAwakeController.deactivate()` lets the screen sleep. `resetForLogout()` clears every flag. On the iPhone `coversRecipe` always equals `isAssistantOpen`, so nothing changes there.

**Rationale:** The interim T034 rule disarmed hands-free beside the panel although the recipe stays on screen (review M2). On another section with the panel open, the composer kept the hidden recipe's chip and the screen stayed awake (review L1). The shell releases the recipe on the tab switch instead of relying on the hidden recipe view in the `TabView`. Caveat: with the panel open, hands-free voice and the assistant's dictation may both want the microphone; that needs a check on a device. Tests: `AssistantRecipeContextTests`, `AppContainerTests`, `DetailScrollViewProbeTests.test_probe_in_two_columns_binds_the_right_column` (scroll commands move the steps column).

---

### 2026-10-13 — iPad: «Коллекции» in a 300 × 420 popover from «…» (spec 081 T037)

**Decision:** On `.padRegular` the recipe's «…» → «Коллекции» shows the phone `CollectionAssignSheet` in a popover through `adaptivePopover`. The popover is 300 × 420 (`IPadLayoutMetrics.collectionsPopoverWidth`, `collectionsPopoverHeight`), set by `iPadPopoverFrame` on the iPad idiom only. The iPhone and a compact iPad window keep the sheet. The layout mode is passed into `RecipeDetailActionsMenu` explicitly, because toolbar items may get a fallback environment. Membership is saved on close, as before. On iPadOS 26 a popover from a bar button grows out of the button and covers it; we accept the system look.

**Rationale:** layout.md gave only a width. The content is a `List`, which has no height of its own, so the popover needs one; 420 matches the assistant history popover. `IPadRecipesSpec.testCollectionsPopoverPersists` covers creation, saving on a tap outside and reopening.

---

### 2026-10-13 — iPad: timers in a popover over the capsule (spec 081 T038, spike S6)

**Decision:** On iPadOS 26.2+ in `.padRegular` a tap on the timers capsule (`tabViewBottomAccessory`) opens the popover (the shell's `timerPopoverShown`) instead of expanding the panel. The popover hangs off an invisible 1 × 1 anchor at the tab view's top-leading corner, with `attachmentAnchor: .rect(.rect(capsuleFrame))` in the anchor's space and `arrowEdge: .bottom`. The arrow points at the capsule with or without the sidebar, and the popover follows the capsule while shown. The content is the phone `MobileTimerPanel(.insetExpanded)`, 380 pt wide and unchanged. Its chevron or a tap outside closes it. A tap on the capsule while it is shown is a tap outside: the capsule lies in the popover's dismiss region. A wide window has no expanded panel: entering `.padRegular` folds an expanded one, leaving it closes the popover, and the popover closes when the capsule goes away. The iPhone and a compact iPad window keep the expanded panel. In DEBUG, `-MobileTimerPanelExpanded=1` opens the popover in a wide window once the capsule is measured; any close drops the request. The capsule and anchor frames live in a plain class held in `@State` (`TimerPopoverGeometry`), and measurements at the origin are ignored.

**Rationale:** Spike S6: a `.popover` inside the accessory never shows. An anchor view the size of the tab view blocked taps on the content under the popover's host, hence a 1 pt anchor with a rect attachment. The accessory is rebuilt on every shell update and first measures off-window at {0, 0}; writing its frame to `@State` updated the shell in a loop and hung the app. `IPadRecipesSpec.testTimersPopoverClosesOnATapOutsideOrTheChevronAndKeepsTheCapsule` runs four open and close rounds and checks that the capsule survives each one (in S6 it once disappeared).

---

### 2026-10-13 — iPad: the cooking table follows the window (spec 081 T039)

**Decision:** On the iPad the cooking table has no forced landscape and no rotation: `cookingOrientations` is `.all`, `requestLandscape` and `unlockOrientation` run only on the phone, and the orientation gate accepts portrait. The one fix is the root frame of `ProcessTableCookingView`: `.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)`. The recipe screen's entry into the table is disabled (TODO 074), so `ProcessTableCookingLayoutTests.testCookingOnIPadFollowsTheWindowInEveryOrientation` hosts the view on the iPad simulator instead. It checks windows of 1210 × 834, 834 × 1210, 597, 400 and 320 pt.

**Rationale:** A flexible frame without `minWidth` takes the larger of the proposal and its child. The view starts with a 420 pt container size, so in a window narrower than 420 pt (⅓, Slide Over) it measured its own matrix and stayed clipped on both sides. With `minWidth: 0` it measures the window. On the iPhone the table is landscape only (at least 667 pt), so nothing changes there.

---

### 2026-10-13 — iPad: recipe edit takes the section like «Развернуть» (spec 081 US5, T041–T043)

**Decision:** On `.padRegular`, when the list and the recipe fit side by side, entering edit expands the recipe the same way «Развернуть» does (`IPadLayoutPolicy.expandsRecipeForEdit`). The list column hides, and a sidebar standing beside the content folds and is remembered. Only «Готово» stays on the bar (Q2); «Развернуть» / «Свернуть» is hidden during edit. The edit uses the T025 columns (panel ≥ 720 pt): the edit header, servings and ingredients go on the left, and the steps editor goes on the right. The formatting bar is in the right column's `.safeAreaInset(edge: .bottom)`, so it sits under the steps and above the keyboard. Below 720 pt the edit is one phone column, at most 720 pt wide and centered. After «Готово» the recipe stays expanded, and «Свернуть» brings back the list and the sidebar that the edit hid (`#recipes/focus`). The sidebar does not return on «Готово» itself, which is a deviation from the literal T041. If the window can't fit the split (the push stack), edit changes nothing in the section. The same applies to a compact window, which is the phone. Coming back to the split during an edit expands the recipe again. A sidebar hidden for the edit stays hidden while the edit goes on and comes back with «Свернуть».

**Rationale:** T043 and `#edit/edit` → `#recipes/focus` describe the state after «Готово» as the expanded recipe, so the expand rules (DECISIONS 2026-10-12) apply as they are, with no second mechanism. A ⅔ landscape window gives the expanded recipe a panel of about 800 pt, so it edits in two columns, as layout.md says. The spec's Independent Test mentions one column there, so this also deviates from it. Tests: `IPadLayoutPolicyTests`, `AppShellCoordinatorTests`, `IPadRecipesSpec.testEditTwoColumns` and `testEditSurvivesSizeClassChange`.

---

### 2026-10-13 — iPad: a recipe edit outlives its view (spec 081 T043, FR-018)

**Decision:** A size class change, or a resize between the split and the phone stack, rebuilds the recipe view in another container. On the iPad the edit lives in `AppShellCoordinator.recipeEdit` (`IPadRecipeEditSession`) and holds:
- the edit view model (the servings and color drafts written on «Готово»);
- the title as typed so far (the title is saved on blur);
- the focus: the title, or the steps editor with its Tiptap selection. The bridge now posts `from`/`to`, and the new `focusAt` command puts the caret back.

A rebuilt view adopts the session and stays in edit. The session keeps a stack of the views in the edit and hears focus notes from views still in it. A focus note makes that view the current one. Text and blur notes count only from the current view. A blur is noted 300 ms after it happens, so a view torn down in between is not heard. Ingredient field focus is not carried over; the ingredient and step text is in the Y.Doc already. `recipeIdsStartedInEdit` stops a recipe created with «+» from re-entering edit after «Готово» when its view is rebuilt (the route still says `openInEditMode`). The iPhone has no session (`iPadEditHost == nil`).

**Rationale:** A rebuild brings up several views of the recipe one after another. A probe showed that the last of them leaving dropped the edit from the view still on screen, so its later focus was lost. A stack plus "a focus note claims the edit" fixes that, and stray notes from a view being torn down are still ignored. Tests: `AppShellCoordinatorTests.testEditSessionHearsOnlyItsOwner` and `testEditSessionGoesBackToTheViewStillInTheEdit`, plus `IPadRecipesSpec.testEditSurvivesSizeClassChange` (regular → compact → regular, title then steps).

---

### 2026-10-13 — iPad: the phone stack keeps the open recipe after a size class change (spec 081 FR-018)

**Decision:** `RecipeListView`'s own `NavigationStack` (iPhone, compact iPad, the iPad push stack) gets `IPadStackPathKeeper`. If the stack appeared with a recipe in its path and SwiftUI empties the path within 1 s, the path is put back once without animation. The modifier is a no-op on the iPhone and when the stack starts empty. Narrowed the same day to 0.5 s after a layout change, see «US4/US5 review fixes».

**Rationale:** When the window leaves the split, the new stack starts with the split's path, and about 150 ms later SwiftUI pops it while the window reflows (`NavigationColumnState.pop`). The compact window then showed the list instead of the open recipe, along with the edit in it. No earlier test covered a compact window with an open recipe. `IPadRecipesSpec.testEditSurvivesSizeClassChange` covers it now.

---

### 2026-10-13 — iPad: recipe edit with the assistant and the popovers (spec 081 US5, owner decision)

**Decision:**
- **Assistant entry.** There is no ✦ during edit: the edit bar is «Готово» only (Q2). The entry is the pinned «Ассистент» tab in the top tab bar, which shows while the edit keeps the sidebar folded, so there is still one assistant entry on screen (FR-021). If the user opens the sidebar mid-edit, the screen has no assistant entry until «Готово»: the sidebar does not list the pinned tab, and the ✦ that would replace it is not on the edit bar. Confirmed by the owner on 2026-10-13: while the sidebar is open mid-edit the screen may have no assistant entry until «Готово» (entry «the assistant during recipe edit stays as it is» below).
- **Panel opened during edit.** The edit stays, and the panel takes the room the list had.
- **Edit started with the panel open.** The edit expands the recipe, and the recipe stays expanded after the panel closes.
- **Timers.** During edit the timers capsule and its popover are hidden, as on the iPhone (`TimerManager.setSuppressPanelSafeAreaInset`). The capsule stays hidden while the rebuilt view's edit continues.
- **Collections.** The «Коллекции» popover cannot be reached during edit, because «…» is not on the edit bar.

**Rationale:** No feature the iPhone lacks, and a single assistant entry. The iPhone edit bar has no ✦ either, and a ✦ next to «Готово» would break Q2. The edit folds the sidebar, so the common case keeps the pinned tab on screen. The sidebar opened by hand mid-edit is rare, and «Готово» brings the ✦ back. The owner decided on 2026-10-13 to keep it.

---

### 2026-10-13 — iPad: the steps column uses the left column's padding (spec 081, owner decision)

**Decision:** In the two-column recipe (reading and edit) the steps column uses the same padding as the left column:
- **Sides.** The steps sections keep their own 16 pt sides, as on the left. The text stays at most 660 pt wide (`stepsMaxWidth`, leading). The extra padding that made the steps 32 pt from the column edges is gone, together with `IPadLayoutMetrics.stepsHorizontalPadding`.
- **Top.** The cap top of «Инструкции» sits on the line where the left column starts. That line is the top of the photo, of its placeholder in edit, or of the legacy banner, or else the cap top of the recipe title. `RecipeStepsColumnMetrics.topPadding` computes the padding from the font metrics (title 28, «Инструкции» title2) and from the 44 pt row the reading header is centred in. The editor's header has no such row.

The phone `StepsSection` and the single column are unchanged.

**Rationale:** The owner asked for it on 2026-10-13. The steps read as a second column of the same card, not as a separate inset panel. A fixed number would drift with Dynamic Type and with the photo, so the padding is computed. In a recipe without a photo, «Инструкции» moves about 6 pt between reading (title cap top) and edit (the placeholder top), because the left column itself starts differently. Measured on portrait shots at 2 px per pt:
- reading: the «Н» of the title and the «И» of «Инструкции» both have their cap top at 343 px (before: «И» at 361 px);
- edit: the «И» is at 332 px, as is the top of the placeholder (before: 343 px);
- the right text starts 17.5 pt from its column edge and the left text 18 pt from its edge, which is 16 pt plus the glyph bearing.

Shots: `tmp/ipad-verify/us5/padding-{reading,edit}-portrait[-before].png`.

---

### 2026-10-13 — Description editor: focus after a rebuild and before the editor is ready (spec 081 US5)

**Decision:** Two races in the steps editor's focus are fixed. They apply on the iPhone too.
- **Chrome unbinding.** `DescriptionEditorChromeState.unbind(bridge:)` replaces `reset()` in `RecipeDescriptionEditorBlock.onDisappear`. An editor that leaves resets the formatting bar's chrome only if the chrome is still bound to it. Before, the delayed `onDisappear` of the old block reset the chrome that the new block had bound. This happens when the iPad rebuilds the steps editor as the recipe switches between one and two columns, for example on ⅔. After that, a tap on the steps brought no formatting bar.
- **Muting incoming focus.** `DescriptionEditorBridge.dismissEditingFocus()` mutes incoming `focus` only when the editor is `.ready`. The mute is lifted by the editor's answer to the `blur` command. An editor that is not ready drops the command, so the mute stayed and swallowed the next real focus. That was the first tap on the steps after editing the title of a recipe that opened in edit.

**Rationale:** Both were found by `IPadRecipesSpec` at ⅔, where the editor is rebuilt while the title has focus. The second one is the likely cause of "the first tap on the steps after the title does nothing", which XCTest also saw on the iPhone. The UI test helper still taps a second time, so this needs a check by hand. Pixels don't change. Behaviour on the iPhone is checked with `scripts/verify-description-editor.sh`. Unit tests in `RecipeScalerNativeTests`:
- `testDismissBeforeTheEditorIsReadyKeepsItsFirstFocus`;
- `testDismissOfAReadyEditorMutesFocusUntilItsBlur`;
- `testChromeStaysWithTheNewerEditor`.

---

### 2026-10-13 — iPad: the assistant during recipe edit stays as it is (spec 081 US5, owner decision)

**Decision:** The current behaviour is accepted as is. The assistant entry is the ✦ in the top tab bar or the sidebar, and it stays reachable during edit. The recipe toolbar in edit shows only «Готово». Nothing more is needed, and the code does not change. Confirmed by the owner on 2026-10-13: the sidebar opened mid-edit may have no assistant entry until «Готово», because it does not list the pinned «Ассистент» tab and the edit bar has no ✦.

**Rationale:** The owner does not need the assistant during edit, but it is fine that it is available. This closes the open point of «recipe edit with the assistant and the popovers» above.

---

### 2026-10-13 — iPad: US4/US5 review fixes (spec 081)

**Decision:** The review of US4 and US5 found eight points. All are fixed except one of the four cleanups, which predates 081:
- **An edit left on another tab** ends once its recipe is no longer selected: `recipesPath` ends an edit session without a view in it whose recipe left the path (a0532b9). Before, a recipe switched off screen (deep link, debug open) kept a stale session, and the next view of that recipe took it up. The reflow's pop right after a layout change waits for `IPadStackPathKeeper`: the edit ends only if that pop is not put back, or a size class change mid-edit would leave edit (6112af2, found by `testEditSurvivesSizeClassChange`).
- **The title no longer takes the focus back** after a one/two-column switch mid-edit. The title's auto-focus request is spent once the title has the focus or the steps editor gets it, on the iPad panel only (068bfb7). No UI test: the switch inside one view needs a real Stage Manager resize.
- **`IPadStackPathKeeper`** no longer undoes the user's «Назад». It puts the path back only when the split or the shell reports a stack rebuild (`noteRecipesStackRebuilt`), within 0.5 s, once, and only to a recipe that still exists. The app's own path resets (deep link, logout, tab reselect, sheet dismiss, delete) cancel it (0d54a2c). A system «Назад» within 0.5 s of a real layout change still looks like the reflow pop.
- **The assistant context** is cleared only by the recipe view that set it (an owner token in `AssistantRecipeContext`). An old view's late `onDisappear` after compact → regular with the assistant sheet no longer clears the new view's recipe (baf5f61).
- **Cleanups:**
  - `RecipeStepsColumnMetrics` measures its fonts once (cf6af4b);
  - the bridge's `focusAt` takes only whole finite positions (`Number.isFinite`, `Math.floor`, ad9e09f);
  - `adoptIPadEditSessionIfNeeded` does not take up an edit that the view has just left with «Готово» (`IPadRecipeEditSession.admits`, fa61a1f).
  - The two `onChange(of: descriptionChrome.isFocused)` handlers in `YDocRecipeDetailView` predate 081, so they stay; see the 081 backlog.
- **`DetailScrollViewProbeTests`** builds the production `YDocRecipeDetailColumns`, which now places the probe in the right column itself (3777e12).
- **The timers popover:**
  - the capsule only opens it, because the toggle-close branch could not run;
  - the DEBUG `-MobileTimerPanelExpanded` request is cleared once the popover shows and on every close path (ff9a72d);
  - the UI test is renamed for what it checks (89218b5).

**Rationale:** Each fix keeps the iPhone as it was. The new code paths need `iPadEditHost`, the split or the popover, and none of them exist on the iPhone. The assistant owner token is invisible there. Unit tests:
- `AppShellCoordinatorTests`: the edit left behind, the reflow pop that keeps it, the stack put back once, path resets cancel it, a deleted recipe is not put back, and the session admits only a view that can be in it;
- `IPadLayoutPolicyTests.testStackPathIsPutBackOnlyRightAfterARebuildAndToALiveRecipe`;
- `AssistantRecipeContextTests` (owner token);
- `DetailScrollViewProbeTests`.

`IPadRecipesSpec.testEditTwoColumns` needs the Simulator.app window open on the iPad. Headless, after `typeText` iPadOS gives the steps editor only the keyboard's shortcuts bar, and the test fails with «No software keyboard». It failed that way at every commit back to the US5 base and passes with the window open. The failure message and `docs/AGENT-WORKFLOW.md` now say so (cf60d16).

---

### 2026-10-13 — iPad: keyboard shortcuts and the menu bar (spec 081 US6)

**Decision:** The iPad gets «Файл», «Рецепт» and «Вид» in the iPadOS menu bar with the shortcuts of layout.md §Меню (`IPadCommands.swift`). Every item runs a path the iPhone already has; there is no «Экспорт в PDF…» (Q3). `AppShellView` publishes `AppCommandActions` and the open `YDocRecipeDetailView` publishes `RecipeCommandActions` with `focusedSceneValue`, both only when `idiom == .pad`, and `.commands` is added to the `WindowGroup` on the iPad only. A `nil` action greys its item out. Details:
- **«Файл»** replaces the system `.newItem` group, so the iPad has no «Новое окно» item: ⌘N, ⇧⌘I, ⇧⌘N and «Поделиться рецептом…».
  - ⌘N does what «Новый рецепт» of the list «+» does (`AppShellCoordinator.createRecipeFromKeyboard`): a new recipe in edit on «Рецепты», whichever list is on screen.
  - ⇧⌘N raises the «Новая коллекция» alert of the iPad shell (`newCollectionRequestEpoch`). It is `nil` before iPadOS 26.2, where that shell does not exist; it closes the profile sheet first.
  - «Поделиться рецептом…» hosts `RecipeShareSheet` in the recipe view (`recipeShareSheet`), so it works without the toolbar button on screen.
- **«Рецепт»** acts on the recipe on screen; with no recipe every item is grey. In an edit only «Готово» (⌘↩) is left, as the edit toolbar has only «Готово». ⌘+ / ⌘− follow the stepper bounds (1…99), ⌘0 is active only when the servings differ from the recipe. ⇧⌘L, ⇧⌘P and «В коллекцию…» run what «…» runs. ⌘⌫ shows the phone delete confirmation; a focused text field keeps ⌘⌫ for its text.
- **⌘↩ lives on the menu item**, not on the «Готово» button (layout.md says the button): one owner per shortcut, and the item shows it while ⌘ is held.
- **«Вид»**: ⌘J, ⌘1–⌘4, ⌘F.
  - ⌘1–⌘4 select a tab without popping the section's stack (`selectTabFromKeyboard`); ⌘4 in a wide window opens the «Моё всё» sheet, as the tab does (FR-004a).
  - ⌘J is the «Ассистент» tab: it opens the assistant and closes it again (the panel in a wide window, the sheet in a narrow one).
  - ⌘F goes to «Рецепты» and focuses the search field of the list on screen (`.searchFocused`, iOS 18+; the item does not exist on iOS 17). In a wide window the expanded recipe collapses and a panel that hides the list closes first; the phone stack pops to its list. The request is taken once, by a list that shows up within 1.5 s (`recipeSearchFocusWindow`). It is `nil` during an edit.
- **⌃⌘S is the system «Показать боковую панель»** item of the iPad sidebar, not our own command (layout.md S2): a second item with ⌃⌘S crashes the app at launch.
- **⌘+ also answers ⌘=**: UIKit matches the `+` item for the =/+ key pressed without ⇧, so the US layout needs no extra ⌘= item (layout.md's fallback). The test presses ⌘=, because `typeKey("+", .command)` adds ⇧. The RU and other layouts are a manual check.
- **The system «Найти» menu is removed** (`UIMainMenuSystem.Configuration.findingPreference = .removed`): it took ⌘F.
- **Held keys do not repeat** a command (`buttonRepeatBehavior(.disabled)`): a repeat closed the assistant ⌘J had just opened.
- **The command values are `Equatable` without their closures.** Two values are equal for the same items and flags (`layoutMode` for «Файл» and «Вид»; the recipe id, «Закрепить»/«Открепить» and «Не гасить экран» for «Рецепт»). The closures read the recipe and its servings when they run. Each body makes new closures, and SwiftUI could not compare such a value: it went through the scene's focus on every layout. Turning the iPad into a compact window mid-edit hung the app in that loop at 100% CPU (`IPadRecipesSpec.testEditSurvivesSizeClassChange`, `IPadAssistantSpec.testSizeClassSwitchKeepsChat`).
- **Titles** are `ipad.menu.*` keys (RU and EN) read with `Bundle.currentLocalizedString`, because commands live outside the in-app language environment.

**Rationale:** Reusing the phone actions keeps one behaviour per command and nothing new on the iPhone, where no command value is published. Tests:
- `AppShellCoordinatorTests`: ⌘1–⌘4 keep the stacks, ⌘4 is the sheet in a wide window, the ⌘F request is taken once within its window, ⇧⌘N closes the profile sheet, the command values compare their items and not their closures.
- `IPadKeyboardSpec` on the iPad simulator: ⌘1–⌘4, ⌘J, ⌘F, ⌘N, ⇧⌘I, ⇧⌘N, ⌘E, ⌘+ (as ⌘=), ⌘−, ⌘0, ⇧⌘L, ⇧⌘P, ⌃⌘A, the inactive «Рецепт» without a recipe and in an edit. `typeKey` on iPadOS 26.3 loses the first key after a launch (tests press a free ⌘K first) and never delivers ⌘↩ or ⌘⌫. `testHostKeys` therefore asks `scripts/verify-ipad-keyboard.sh` to send them as HID events with AXe and checks the result: ⌘↩ ends an edit from the title and from the steps editor; ⌘⌫ shows the confirmation on a recipe (the test cancels it) and asks nothing without one; ⌘⌫ in the search field deletes its text. The menu bar itself is not in the accessibility tree, so its look is a manual check.
- `PhoneKeyboardSpec` on the iPhone: the iPad shortcuts change nothing there, and ⌘A in the search field shows the keys reach the app.

The edit test types an ingredient in the edit of a ⌘N recipe. A recipe created over REST is in the old format and read-only, and the local backend rejects ingredients sent over REST for it, so the test cannot seed one. Two pre-existing findings on the way, left as they are:
- `RecipeTitleTextField` takes the focus back after an incidental blur. A tap from the focused title of a new recipe into the new-ingredient row puts the caret in the row for a moment, then back in the title. The test lets the title go with its keyboard «Готово» first.
- `.accessibilityIdentifier(recipeEditNewIngredientRow)` on the row covers its children: the name and amount fields and «Return» report the row's identifier, so `recipe_edit_new_ingredient_submit` never matches.

---

### 2026-10-13 — iPad: multitasking in one window (spec 081 US7)

**Decision:** The width matrix of layout.md §Матрица приёмки is walked in one running app, not by relaunching at each width.
- **A live width channel (DEBUG only).** With `-DebugWindowWidthLive=1` the app reads the Darwin state of `ru.recipescaler.debug.window-width` (0 is the whole window), narrows its root to it (`appLayoutModeRoot`) and posts back the width it applied. `IPadMultitaskingSpec` moves through the widths and checks, at each one, the tabs or bottom bar, the list column, the recipe columns, the assistant panel, and that the open recipe and its collection are kept (SC-005).
- **Host screenshots.** XCTest's screenshot of a landscape window is a cropped portrait buffer, so the test prints `IPAD_MATRIX_SHOT <n> <name>` and waits; `scripts/verify-ipad-matrix.sh` (also `verify-ipad-layout.sh --matrix`) takes `simctl io screenshot`, turns landscape shots upright with `sips`, and answers on `ru.recipescaler.debug.matrix-shot`. The measured rows go to `matrix.txt`. A fixture self-test runs in `policy-check`.
- **The orientation is the window's.** The recipes split measured its height inside the safe area, so the ⅔ landscape window (776 × 834 on the 11″) lost the bars' height, read as landscape and gave the list ⅓ (320 pt). It now measures to the window's top and bottom edges: the window is taller than wide, the list takes ½, as the matrix says. The keyboard still never turns portrait into landscape.
- **One window stays** (Q4): no scene manifest, no `UIApplicationSupportsMultipleScenes`, one `WindowGroup`, «Новое окно» replaced away in `IPadCommands`.

**Rationale:** The simulator cannot script Split View, Slide Over or Stage Manager, and relaunching at each width would not show what a resize keeps. The stand-in narrows only the SwiftUI root, so it has limits, and these stay manual checks on a device:
- sheets are presented from the full window (the compact assistant is a form-sheet card, not the phone sheet);
- below the full width iPadOS folds the sidebar into the top tab bar, which a real ⅔ window may not do;
- the menu bar is not in the accessibility tree.

The old shell (iPadOS 17.0–26.1, spec.md Q1) could not be checked on the simulator. On the iOS 18.4 runtime the app crashes at launch: dyld cannot load `/usr/lib/swift/libswiftWebKit.dylib`. The app links it through the Swift overlay `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:) async` (deployment target 17), and the 18.4/18.5 simulator runtimes keep the library in `System/Cryptexes/OS/usr/lib/swift`, where dyld does not look. It is a known runtime bug (WebKit 293831; Apple forums threads 780073 and 785964), and devices are reported to run. No iOS 17 runtime is installed. Both are owner checks on a device.

---
