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