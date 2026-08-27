# Code Review: master — spec 073 assistant tool-status UI

## Summary

Cross-platform spec 073 adds visible tool-status rows to native assistant (web parity). Core happy path — `toolStart` row insertion, processing shimmer, i18n map, `applyFinal` retention — is **sound**. Review covered **Business Logic**, **Standards**, **Architecture**. Skipped **Security** (no auth/input surface) and **Performance** (no hot-path change beyond message list).

**Initial verdict:** Changes Requested (2 high issues in optimistic cleanup on errors).

**Post-fix:** Both high issues addressed — NDJSON `.error` now throws to unified `send()` catch; all `optimistic-*` removed on any stream failure.

## Areas reviewed

| Area | Result |
|------|--------|
| Business Logic | 2 high (fixed) |
| Standards | 0 critical/high; medium doc gaps |
| Architecture | OK |
| Security | Skipped — N/A |
| Performance | Skipped — N/A |

## Findings (sorted by priority)

### High (fixed)

1. **[Business Logic] Stream `.error` left partial optimistic state**

   - **Impact:** User bubble + processing shimmer could remain after server stream error; diverged from web/spec 073.
   - **Fix:** `.error` NDJSON event now `throw APIError.serverError` (matches web `respondStream`); `send()` catch removes all optimistics.

2. **[Business Logic] `send()` catch only removed optimistic user bubble**

   - **Impact:** Orphan tool-status rows and processing placeholder after transport failures.
   - **Fix:** `removeAllOptimisticMessages()` clears all `optimistic-*` prefixes before error bubble; composer restored.

### Medium (deferred)

3. **[Standards] `plan.md` missing full Spec Kit sections** — doc-only; optional follow-up.

4. **[Standards] No `tasks.md` for 073** — doc-only.

5. **[Standards] Monorepo kanon spec path** — exists at `recipe-scaler/specs/073-…` when sibling checkout present.

### Low (deferred)

6. Mixed 043 + 073 diff scope — commit hygiene.

7. Incomplete i18n alias test coverage — code is 1:1 with web.

8. Stale `assistant.thinking` key — harmless.

## Recommendation

**Approved** after high-priority fixes. Re-run build + `AssistantToolStatusI18nTests` for verification.
