# Code Review: master

**Scope:** Linear issues labeled `to check` — MIK-130, MIK-134, MIK-132, MIK-147, MIK-150 (+ uncommitted MIK-129 SyncErrorCode work)

**Commits reviewed:** `352147c` … `966e000` + working tree diff

**Review model:** inherit (requested `glm-5.2` unavailable in Task subagent model list)

**Date:** 2026-06-20

---

## Summary

Changes materially address the original review findings: dead bridge code removed (MIK-134), format detector hardened (MIK-147), routing folder fixed (MIK-150), timer sprawl partially consolidated (MIK-132), session/load teardown improved (MIK-130), and `SyncErrorCode` replaces substring UI leaks in edit alerts (MIK-129).

**Overall risk: medium.** No critical security defects, but two ship blockers remain in uncommitted work:

1. **Async deinit unregister** can remove a *newer* description-editor session for the same `recipeId` after fast navigation.
2. **Ownership errors** still surface raw English server text in `ConnectionState` UI despite typed `SyncErrorCode`.

Uncommitted MIK-130/132 fixes should be committed before closing Linear tasks.

---

## Findings (sorted by priority)

### High

1. **[Business Logic / Security]** Async `DescriptionEditorDeinitCleaner` can unregister a live editor session
   - **Impact:** Fast close→reopen same recipe: bridge B is registered in SwiftUI but removed from `descriptionEditorSessions`. Remote Yjs updates miss the live WebView; wire-export scheduling may treat the recipe as editor-less.
   - **Recommendation:** Unregister only if `descriptionEditorSessions[recipeId]?.bridge === self` (generation token). Prefer synchronous cleanup in `teardown()`; make deinit path idempotent.

2. **[Security / Standards / Architecture]** Raw server `sync_error` text still reaches connection UI for ownership failures
   - **Impact:** `setConnectionState(.error(message), …)` passes English `payload["error"]` into `ConnectionState.displayLabel` (`"Sync error: %@"`). Partially undoes MIK-129 i18n goal; server/MITM can inject arbitrary text into trusted UI.
   - **Recommendation:** Use `code.localizedMessage` for connection-level errors. Same pattern for `auth_error` paths.

3. **[Architecture / Standards]** Duplicate `sync_error` Socket.IO handlers
   - **Impact:** Inline handler in `connectSocket()` (~1321) and `SyncEventHandler` both fire. Double logging, split behavior, bypasses typed pipeline for collection flag reset.
   - **Recommendation:** Remove inline handler; route exclusively through `SyncEventHandler` → `handleSyncError`.

4. **[Architecture]** `connectionTimerTask` shared between FSM timeouts and network-regain debounce
   - **Impact:** Network flicker during `.connecting`/`.authenticating` cancels engine/auth watchdog and repurposes timer — same fragility class MIK-132 aimed to fix.
   - **Recommendation:** Split into `connectionStepTimer` (owned by `transition`) and `networkReconnectDebounceTask`.

5. **[Architecture]** `ConnectionStep` FSM incomplete; `attempt` unused; dual state with `ConnectionState`
   - **Impact:** `reconnectAttempt` updates UI `.reconnecting` but not `ConnectionStep`; `attempt` always `1`. Session guards and UI state can diverge.
   - **Recommendation:** Document mapping table or fold `.reconnecting` into `ConnectionStep`; increment `attempt` on reconnect or remove field.

### Medium

6. **[Security]** Legacy substring classification triggers destructive actions without validated `code`
   - **Impact:** Crafted English in `payload["error"]` can trigger `.recipeDeleted` (tombstone, queue clear) or `.ownershipFailed` via `contains` matching.
   - **Recommendation:** Require typed `code` for destructive actions when server supports it; gate legacy path behind capability flag.

7. **[Security / Standards]** Full sync error payloads logged with public visibility
   - **Impact:** Server-controlled strings in `AppLog` NDJSON (DEBUG exportable) and `os.Logger` with `.public`.
   - **Recommendation:** Log `code` + truncated/redacted message; use `UserIdFormatter.redactDocKey` for recipe ids in logs.

8. **[Business Logic]** Nil-bridge session window can trigger spurious wire export
   - **Impact:** Between deinit and async unregister, `scheduleDescriptionWireExportIfNeeded` may request export for closed editor.
   - **Recommendation:** Treat `bridge == nil` as inactive in wire-export scheduling; prune synchronously in `teardown()`.

9. **[Performance]** `handleSyncError(.generic)` sleeps 5s on `@MainActor`
   - **Impact:** Error storms block entire sync service and MainActor work.
   - **Recommendation:** Move delay off MainActor; hop back only for `requestDocumentReload`.

10. **[Performance]** `migratePlistSyncKeysIfNeeded` scans all UserDefaults keys once at bootstrap (352147c)
    - **Impact:** O(all keys) spike on first login after upgrade for users with many `lastServerDocBytes:*` keys.
    - **Recommendation:** Targeted deletion per known recipe ids instead of `dictionaryRepresentation()`.

11. **[Performance / MIK-130]** Per-recipe dict entries not cleaned on recipe delete
    - **Impact:** `documentLoadTasks`, `wireSnapshotRefreshTasks`, `descriptionEditorSessions` can linger until global teardown.
    - **Recommendation:** Add `cancelPendingWork(forRecipeId:)` on delete paths.

12. **[Standards]** `sync.error.*` keys missing from `LocalizationConsistencyTests`
    - **Impact:** en/ru parity regression net gap for five new keys.
    - **Recommendation:** Add to `testCriticalKeysResolveInBothLanguages`.

13. **[Standards]** Orphaned `edit.error.invalidUpdate` / `edit.error.ownership` / `edit.error.deleted` xcstrings keys
    - **Impact:** Duplicate namespace confusion after migration to `sync.error.*`.
    - **Recommendation:** Remove or document deprecation in `sync-error-codes.md`.

### Low

14. **[Business Logic]** Redundant `completePendingDocumentLoad(merged: false)` after successful load — no double-resume, but misleading.
15. **[Business Logic]** Legacy `"Empty"` substring false positives — pre-existing; tighten or prioritize server `code`.
16. **[Business Logic]** Removed 15s connecting watchdog — marginal auth retry loss in narrow 13–15s engine-connect window.
17. **[Performance]** `pruneStaleDescriptionEditorSessions` O(n) on register/unregister — acceptable at n≈1.
18. **[Performance]** `refreshWireSnapshotForRecipe` debounce scans full offline queue — O(queue size) per edit.
19. **[Standards]** `docs/I18N.md` lacks `SyncErrorCode` subsection; `plan.md` missing MIK-129 stage.
20. **[Standards]** Contract gaps: no `sync-error-codes.json` instance; schema `required: ["code","error"]` contradicts back-compat.
21. **[Standards]** `writeSyncStates[recipeId] = .error(message)` stores raw English — no current UI leak, latent risk.
22. **[Standards]** `YjsMemoryLeakTests` uses force-unwrap and fixed 100ms sleep — minor flakiness risk.

### Resolved (OK to close after commit)

| Issue | Verdict |
|-------|---------|
| **MIK-134** Dead local-update bridge | ✅ Removed `installLocalUpdateBridge`, `setOnLocalUpdateHandler` |
| **MIK-147** Non-object JSON as v1.0 | ✅ Throws `invalidJSON`; test added |
| **MIK-150** Empty Routing/ folder | ✅ `DeepLinkRouter` in `Routing/`; pbxproj wired |
| **MIK-132** Timer sprawl | ⚠️ Partially — 5→1 connection timer; FSM incomplete; other timers remain |
| **MIK-130** Unbounded registries | ⚠️ Partially — teardown/dedup/deinit cleaner; deinit race + delete cleanup gaps |

---

## Checklist

- [x] Security vulnerabilities — ownership UI injection, legacy substring trust boundary
- [x] Business logic correctness — deinit unregister race is ship blocker
- [x] Performance bottlenecks — MainActor 5s sleep; UserDefaults full scan
- [x] Code follows project standards — AppLog partial; i18n keys incomplete in consistency tests
- [x] Error handling comprehensive — typed routing correct; connection path leaks English
- [x] Tests adequate — strong unit tests; weak integration for handler→UI path
- [x] Documentation updated — sync protocol/ARCHITECTURE yes; connection FSM no
- [x] Architecture appropriate — partial FSM consolidation; duplicate handlers
- [ ] Deployment concerns — uncommitted changes must land before production

---

## Recommendation

**Changes Requested**

Rationale: Core direction is sound and closes most original review findings. Before marking `to check` tasks Done and merging uncommitted work:

1. Fix **deinit unregister identity** (High #1) — ship blocker for MIK-130.
2. Route **ownership errors** through `code.localizedMessage` in `ConnectionState` (High #2).
3. **Remove duplicate `sync_error` handler** (High #3).
4. **Commit** uncommitted MIK-130/132/129 changes and add `LocalizationConsistencyTests` entries.
5. Split **connection timer** ownership (High #4) — can follow in a small follow-up.

MIK-134, MIK-147, MIK-150 are ready to close. MIK-132 and MIK-130 need the above fixes + commit.

---

## Review subagents

| Area | Agent |
|------|-------|
| Security | [security to-check](53d3810f-4361-457e-a4a7-488e5eacf099) |
| Business Logic | [business logic to-check](c2d71c0f-a470-435d-bc94-c9d1f29f675d) |
| Performance | [performance to-check](d81ac340-7764-4b31-9e04-a911576d08d8) |
| Architecture | [architecture to-check](0f33e04c-54f6-4bc8-af22-ecb2d82ede6d) |
| Standards | [standards to-check](16ed83fa-e2a1-496d-b180-c68ac7bdda51) |
