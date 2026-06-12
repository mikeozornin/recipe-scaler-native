# Code Review: 019-recipe-description-inline-edit

**Model:** GLM-5.1 (composer-2.5-fast)  
**Date:** 2026-06-11  
**Scope:** Full project diff — 36 files, +1750 / -684 lines  
**Reviewers:** 5 parallel subagents (Security, Business Logic, Performance, Architecture, Standards)

---

## Summary

The branch adds inline description editing with rich text (bold, italic, highlight, headings, lists, links), timer/ingredient markup references, and a WebView-based editor bridge. The overall quality is **moderate** — the feature works end-to-end, but has **2 critical**, **15 high**, **24 medium**, and **14 low** findings across security, correctness, performance, architecture, and standards.

**Risk level: Changes Requested** — critical and high findings must be addressed before merge.

---

## Findings (sorted by priority)

### Critical

#### 1. [Business Logic] Timer Span Matching Non-Determinism
- **File:** `description-editor-bridge.js` L875-895
- **Impact:** `timerSpanMatches()` uses multi-criteria matching that returns the WRONG timer span when multiple timers share the same duration/type. The fallback match (no timerId, matching duration+type without text/value) returns the first DOM-order match — not the one the user interacted with. Unlinking or renaming a timer can corrupt user data.
- **Recommendation:** Always pass `timerId` for existing timer operations. Assign timerId during normalize/repair for legacy markup missing one.

#### 2. [Business Logic] Data Loss on Fragment Rebuild
- **File:** `description-editor-bridge.js` L488-516
- **Impact:** `pushLocalEdit()` calls `htmlToFragment()` → `clearFragment()` — deleting ALL content — then rebuilds from DOM innerHTML. During the clear+rebuild window, the fragment is empty. If a remote update arrives or the conversion fails on malformed HTML, data is permanently lost.
- **Recommendation:** Diff-based approach (compare current fragment to desired state, apply minimal edits), or wrap in a transaction with error recovery that restores the previous fragment state on failure.

#### 3. [Standards] QRScannerView English-Sentence Localization Keys
- **File:** `QRScannerView.swift`
- **Impact:** Localization keys are full English sentences (e.g., `"Scan QR code from recipe website"`). This violates the project's key naming convention (kebab-case/short keys). Translators see English sentences as keys, making maintenance error-prone and confusing.
- **Recommendation:** Replace with short structured keys like `"qr-scanner.title"`, `"qr-scanner.instruction"`, etc.

---

### High

#### 4. [Architecture] God File: description-editor-bridge.js (~1142 lines)
- **File:** `description-editor-bridge.js`
- **Impact:** Single JS file handles 6 responsibility domains: Y.js sync, DOM rendering, HTML parsing, selection management, markup CRUD, and format commands. Extremely difficult to maintain, test, or extend.
- **Recommendation:** Split into modules: `sync.js`, `render.js`, `parser.js`, `selection.js`, `markup.js`, `commands.js`. Use ES modules or IIFE namespace pattern.

#### 5. [Architecture] Duplicated Amount/Ratio Logic in JS and Swift
- **Files:** `description-editor-bridge.js`, `DescriptionMarkupFlow.swift`, `IngredientNutritionDisplay.swift`
- **Impact:** Amount parsing (`parseAmount`/`formatAmount` in JS, `Double` formatting in Swift), ratio computation, and ingredient label generation are independently implemented on both sides. Divergent logic produces different display values for the same data.
- **Recommendation:** Single source of truth for display logic. Either compute labels in JS and pass to Swift, or use a shared specification. At minimum, add cross-platform tests.

#### 6. [Architecture] God View: YDocRecipeDetailView (~1210 lines)
- **File:** `YDocRecipeDetailView.swift`
- **Impact:** Mixes recipe detail rendering with markup orchestration, timer flows, ingredient click handlers, and chrome suppression. Unmaintainable at scale.
- **Recommendation:** Extract markup orchestration into `DescriptionMarkupCoordinator`, ingredient interactions into `IngredientInteractionHandler`, etc.

#### 7. [Performance] Full Fragment Clear+Rebuild on Every Edit
- **File:** `description-editor-bridge.js` L488-516
- **Impact:** Every 400ms debounced edit cycle calls `clearFragment()` then rebuilds from scratch. This creates CRDT operation bloat proportional to document size × edit frequency. For a 500-word description, each keystroke generates hundreds of delete+insert operations in the Y.js history.
- **Recommendation:** Diff-based patching — compare current fragment to desired state and apply only changed nodes/attributes.

#### 8. [Performance] Unthrottled `selectionchange` Bridge Messages
- **File:** `description-editor-bridge.js`
- **Impact:** `selectionchange` fires on every cursor move/selection change, calling `postSelectionState()` which runs expensive `queryCommandState` DOM queries and posts a message to Swift. No throttle/debounce. During rapid cursor movement (arrow keys, dragging selection), this can fire 30-60×/sec.
- **Recommendation:** Throttle `postSelectionState` to ~100ms via `requestAnimationFrame` or a simple timer.

#### 9. [Business Logic] Ingredient Markup Round-Trip Drops Marks
- **File:** `description-editor-bridge.js` L374-378, L256-261
- **Impact:** When converting ingredient HTML → Y.XmlElement, no text children or label fallback is stored. If `data-original-amount` or `data-ratio` is missing, the display is empty — the user's originally selected text is permanently lost.
- **Recommendation:** Store the original selected text as a fallback attribute (`data-label`) or keep a text child for the label.

#### 10. [Business Logic] Race Condition: holdSelectionForMarkup + Debounce
- **File:** `description-editor-bridge.js` L845-849, L865-868
- **Impact:** Between `prepareMarkupSelection` and the actual markup command, a 400ms debounced `pushLocalEdit` could fire, calling `htmlToFragment()` which rebuilds the DOM. The saved selection range references stale nodes.
- **Recommendation:** Skip `schedulePush` during markup preparation, or snapshot selected text content instead of relying on DOM range restoration.

#### 11. [Business Logic] normalizeFragmentForWeb Loses Timer Text Children
- **File:** `description-editor-bridge.js` L455-465
- **Impact:** Normalization strips text children from `ingredient` elements but NOT from `timer` elements. Web Tiptap expects timers as inline nodes without text. Inconsistency causes web-side rendering issues.
- **Recommendation:** Also strip text children from timer elements during normalization. Ensure `pendingRepairUpdate` is flushed before editor destruction.

#### 12. [Business Logic] No Validation of ingredientId Reference on Markup
- **File:** `YDocRecipeDetailView.swift` L711-721
- **Impact:** Clicking an orphaned ingredient reference (deleted ingredient) silently does nothing. Users get no feedback and no way to fix the dead link from the UI.
- **Recommendation:** Add fallback UI for orphaned references ("Ingredient deleted" with "Unlink" option). Validate ingredientId before creating markup.

#### 13. [Standards] Typography Violations — Raw `.font()` Instead of Helpers
- **Files:** `QRScannerView.swift`, `DescriptionTimerStartPopover.swift`, `RecipeDetailImageSection.swift`, others
- **Impact:** Multiple files use `.font(.caption)`, `.font(.caption2)`, `.font(.title3)` directly instead of the project's `.appBody()`, `.appFootnote()`, `.appHeadline()` helpers. Bypasses centralized typography and line-spacing standards.
- **Recommendation:** Replace all raw `.font()` calls with the corresponding `AppTypography` helpers.

#### 14. [Standards] `String(localized:)` in SwiftUI Views
- **Files:** `QRScannerView.swift`, `ServingsStepperView.swift`, possibly others
- **Impact:** `String(localized:)` is a Foundation API that doesn't read SwiftUI's `\.locale` environment. On language switch, these strings stay stale until the view is recreated.
- **Recommendation:** Use `Text("key")` (LocalizedStringKey) or `Bundle.currentLocalizedString("key")` for runtime strings.

#### 15. [Standards] Navigation Title Violations
- **Files:** `EditIngredientNutritionSheet.swift`, possibly others
- **Impact:** Using `.navigationTitle(Text("key"))` instead of `.localizedNavigationTitle("key")`. Title "sticks" on old language after runtime language switch because `Text("key")` doesn't change identity.
- **Recommendation:** Use `.localizedNavigationTitle("key")` for all navigation titles per AGENTS.md.

#### 16. [Standards] Hardcoded Unlocalized Strings
- **Files:** `DescriptionMarkupFlow.swift` L348, `DescriptionTimerStartPopover.swift` L46, `RecipeDescriptionEditorBlock.swift` L47
- **Impact:** `Text("Start timer")`, `Text("Instructions")` are hardcoded English, not localization keys. Stays English when app language is Russian.
- **Recommendation:** Add keys to `Localizable.xcstrings` and use `Text("start.timer")`, `Text("instructions")`.

#### 17. [Standards] Key Naming Inconsistency in Localizable.xcstrings
- **File:** `Localizable.xcstrings`
- **Impact:** Mix of naming conventions — some keys use kebab-case (`"description-editor.keyboard-done"`), others use full English sentences (`"Scan QR code from recipe website"`). Inconsistent key structure makes maintenance harder.
- **Recommendation:** Standardize on short kebab-case keys. Rename sentence-style keys.

#### 18. [Standards] Accessibility Gaps
- **Files:** `DescriptionFormattingBar.swift`, `RecipeNutritionBlockView.swift`
- **Impact:** Some interactive elements lack accessibility identifiers or meaningful labels. Formatting bar buttons may not have `accessibilityLabel`. Nutrition block view has no identifiers for automated testing.
- **Recommendation:** Add `AccessibilityIdentifiers` entries and `.accessibilityLabel()` where missing.

---

### Medium

#### 19. [Security] Debug Logging in Release Builds
- **File:** `YDocRecipeDetailView.swift`, `YjsSyncService.swift`
- **Impact:** `DebugSessionNDJSONLog.write()` calls are NOT wrapped in `#if DEBUG`, leaking recipe metadata (titles, ingredient names) to OS log in release builds.
- **Recommendation:** Wrap all `DebugSessionNDJSONLog.write()` calls in `#if DEBUG`.

#### 20. [Security] WKWebView No Navigation Policy
- **File:** `DescriptionEditorWebView.swift`
- **Impact:** No `WKNavigationDelegate` with `decidePolicyFor navigationAction` to block arbitrary URL loads. A malicious description could trigger navigation to external URLs.
- **Recommendation:** Add navigation policy that blocks all URL loads except the local HTML file.

#### 21. [Security] `javascript:` Scheme URLs Pass Through Unvalidated
- **File:** `description-editor-bridge.js` — `resolveLinkHref()`
- **Impact:** Link hrefs starting with `javascript:` pass through the DOM→Y.js pipeline without validation. If rendered in a context where links are clickable, this is an XSS vector.
- **Recommendation:** Filter `javascript:` URLs in `resolveLinkHref()`. Strip or neutralize them.

#### 22. [Security] HTML Unsanitized on Remote Update Apply
- **File:** `description-editor-bridge.js`
- **Impact:** When remote Y.js updates are applied, `renderFragment()` generates HTML from Y.js data. While the source is the CRDT (not user input), a compromised peer could inject arbitrary HTML attributes through the Y.js fragment.
- **Recommendation:** Sanitize rendered HTML before inserting into the DOM, or validate Y.js attributes against an allowlist during render.

#### 23. [Performance] CRDT Operation Batching Needed
- **File:** `description-editor-bridge.js`
- **Impact:** Y.js operations during fragment rebuild are batched in a `transact()` block, but individual attribute operations within `normalizeFragmentForWeb` are not batched. Each `setAttribute` generates a separate CRDT operation.
- **Recommendation:** Wrap repair operations in a single `ydoc.transact()` call.

#### 24. [Performance] Binary Update Serialization Inefficiency
- **File:** `DescriptionEditorWebView.swift`, `DocumentManager.swift`
- **Impact:** Y.js updates are serialized as base64 strings via JSON bridge. For large documents, this is ~33% larger than binary. Each update round-trips through JSON stringify/parse.
- **Recommendation:** Consider using `Uint8Array` transfer or at minimum profile whether base64 overhead matters for typical description sizes.

#### 25. [Performance] SwiftUI Re-render Scope — 18 @State Properties
- **File:** `YDocRecipeDetailView.swift`
- **Impact:** The detail view has ~18 `@State` properties. Changing any one causes the entire view body to re-evaluate. With complex ingredient lists and formatting bars, this can cause visible jank.
- **Recommendation:** Extract subviews with their own `@State` to narrow re-render scope. Use `@StateObject` for complex state.

#### 26. [Performance] Redundant `measureContentHeight` Calls
- **File:** `description-editor-bridge.js`
- **Impact:** `measureContentHeight()` is called after every command and after most state changes. Each call reads `scrollHeight` which can trigger layout recalculation. Multiple calls per interaction cycle (e.g., after `toggleBold`, `captureSelection`, `postSelectionState`).
- **Recommendation:** Debounce `measureContentHeight` or call it only once per event cycle via `requestAnimationFrame`.

#### 27. [Performance] Ingredient List Computed Property Recalculation
- **File:** `YDocIngredientsSection.swift`
- **Impact:** Nutrition display properties (`IngredientNutritionDisplay`) are recomputed on every view body evaluation. For recipes with many ingredients, this is O(n) per render cycle.
- **Recommendation:** Cache or memoize nutrition computations. Use `Equatable` conformance to skip unchanged rows.

#### 28. [Business Logic] `formatAmount` Locale Inconsistency
- **File:** `description-editor-bridge.js` L86-90, L747-751
- **Impact:** Amounts always use `.` as decimal separator. `parseAmount` converts `,` → `.` on input, but `formatAmount` never outputs `,`. For Russian users expecting `,`, this looks wrong.
- **Recommendation:** Document that internal representation uses `.`, with locale formatting at the display layer.

#### 29. [Business Logic] `pendingRepairUpdate` Timing Fragility
- **File:** `description-editor-bridge.js` L986-994
- **Impact:** Repair updates are sent as incremental diffs during init before `ready = true`. If the server expects full state sync first, this could cause issues.
- **Recommendation:** Verify server handles incremental init updates. Consider batching with initial state.

#### 30. [Business Logic] Selection Restore May Fail After Sheet Dismissal
- **File:** `description-editor-bridge.js` L1034-1038, L815-825
- **Impact:** On iOS, sheet dismissal steals focus from WKWebView. `holdSelectionForMarkup` tries to re-grab via `requestAnimationFrame`, but timing is unreliable. Markup may be inserted at wrong position.
- **Recommendation:** Store selection as character offset pair (relative to content) instead of DOM Range.

#### 31. [Business Logic] `beforeinput` Guard Blocks Editing Near References
- **File:** `description-editor-bridge.js` L1060-1072
- **Impact:** The guard checks only `anchorNode`, not `focusNode`. Cross-boundary selections can partially destroy reference spans. Adjacent typing may be incorrectly blocked.
- **Recommendation:** Check both anchor and focus nodes. Handle cross-boundary selections explicitly.

#### 32. [Business Logic] Servings Cap Mismatch: 99 (iOS) vs 999 (backend)
- **Files:** `YDocIngredientsSection.swift` (L292, L310), `DocumentManager.swift`
- **Impact:** iOS UI caps servings at 99, backend allows 999. Web recipes >99 servings display correctly but truncate to 99 on iOS edit.
- **Recommendation:** Align the cap — 99 or 999 everywhere.

#### 33. [Architecture] CRDT Repair Non-Idempotency
- **File:** `description-editor-bridge.js`
- **Impact:** `normalizeFragmentForWeb()` is not idempotent — running it twice can produce different results. If repair triggers on every init, repeated opens may keep mutating the fragment.
- **Recommendation:** Make repair idempotent by checking if normalization is needed before applying changes.

#### 34. [Architecture] runCommand Boilerplate
- **File:** `description-editor-bridge.js`
- **Impact:** Every case in `runCommand` has identical `editorEl.focus() + restoreSelection()` boilerplate (14+ cases). Error-prone to maintain.
- **Recommendation:** Extract common pre-command logic into a wrapper function.

#### 35. [Architecture] Distributed Chrome Suppression Logic
- **File:** `YDocRecipeDetailView.swift`
- **Impact:** Chrome suppression for editing mode is spread across multiple `@State` booleans and conditional modifiers. Hard to reason about all possible states.
- **Recommendation:** Consolidate into a single `editMode` enum with associated values.

#### 36. [Architecture] Inconsistent Error Propagation JS→Swift→ViewModel
- **Files:** `description-editor-bridge.js`, `DescriptionEditorWebView.swift`, `RecipeEditViewModel.swift`
- **Impact:** JS errors are swallowed silently. Swift bridge `evaluateJavaScript` errors are logged but not surfaced to the ViewModel. User sees no feedback on failure.
- **Recommendation:** Define error types, propagate through the chain, show user-facing alerts for critical failures.

#### 37. [Standards] Key Naming Inconsistency in AccessibilityIdentifiers
- **File:** `AccessibilityIdentifiers.swift`
- **Impact:** New entry `descriptionEditorKeyboardDone` uses camelCase while the rest of the enum uses camelCase — but the values use snake_case inconsistently (`"description_editor_keyboard_done"` vs others).
- **Recommendation:** Verify all accessibility ID strings follow the project's kebab-case convention (per E2E testing rules in user preferences).

#### 38. [Standards] Code Duplication in Nutrition Display
- **Files:** `RecipeNutritionBlockView.swift`, `EditIngredientNutritionSheet.swift`
- **Impact:** Nutrition row rendering logic is duplicated between the detail view and the edit sheet. Changes to one need to be mirrored in the other.
- **Recommendation:** Extract shared nutrition row component.

#### 39. [Standards] UIKit Swizzle Replacing Deleted Reorder Table
- **File:** Related to `IngredientEditReorderTableView.swift` deletion
- **Impact:** The deleted UIKit reorder table is replaced by SwiftUI `List` + `.onMove`. Verify the swizzle in `Bundle+Language.swift` doesn't reference the deleted class.
- **Recommendation:** Verify no runtime references to `IngredientEditReorderTableView` exist in swizzle or extension code.

#### 40. [Standards] Incomplete Typography Migration
- **Files:** `AppSymbol.swift` (migrated), others not yet
- **Impact:** `AppSymbol.make()` was correctly migrated from `.font(AppTypography.body)` to `.appBody()`, but other files still use raw `.font()`.
- **Recommendation:** Complete the migration across all changed files.

#### 41. [Standards] Undocumented Logic Change in RecipeEditViewModel
- **File:** `RecipeEditViewModel.swift`
- **Impact:** The diff shows a change to servings handling but no documentation or comment explaining why.
- **Recommendation:** Add a brief comment for non-obvious logic changes.

#### 42. [Security] `postMessage` Payload Structure Change
- **File:** `description-editor-bridge.js`
- **Impact:** `post()` function changed from `Object.assign({ type: type }, payload)` to `Object.assign({}, payload, { type: type })`. If payload contains a `type` key, it will now be overwritten by the outer type. Previously payload's `type` would win.
- **Recommendation:** Verify no callers pass `type` in their payload. If they do, this is a breaking change.

---

### Low

#### 43. [Security] `escapeHtml` Could Be Single-Pass
- **File:** `description-editor-bridge.js`
- **Impact:** `escapeHtml()` chains multiple `.replace()` calls. For large texts, this iterates the string multiple times.
- **Recommendation:** Use a single-pass regex with a replacement map for marginal improvement.

#### 44. [Security] Debug `console.log` Statements May Remain
- **File:** `description-editor-bridge.js`
- **Impact:** Some `console.log`/`console.warn` statements may remain in production JS. While not a security issue, they clutter the WebView console.
- **Recommendation:** Audit and remove or gate behind a debug flag.

#### 45. [Security] `postMessage` Handler Has No Schema Validation
- **File:** `DescriptionEditorWebView.swift`
- **Impact:** Message handler accepts any JSON from JS. Malformed messages could cause runtime errors in Swift.
- **Recommendation:** Add basic schema validation (required fields, types) in the message handler.

#### 46. [Security] Y.js Update Origin Not Authenticated
- **File:** `DocumentManager.swift`
- **Impact:** Y.js updates from the server are applied without origin verification. A compromised server could inject arbitrary CRDT operations.
- **Recommendation:** Acceptable for current offline-first model, but document this trust assumption.

#### 47. [Performance] Regex Caching in JS
- **File:** `description-editor-bridge.js`
- **Impact:** Several regex patterns are created inline (e.g., in `formatAmount`, `parseAmount`). For hot paths, these are recompiled on each call.
- **Recommendation:** Hoist regex literals to module scope.

#### 48. [Performance] Nutrition Debounce Interval
- **File:** `EditIngredientNutritionSheet.swift`
- **Impact:** Nutrition editing debounce may be too aggressive or too conservative for the typing experience.
- **Recommendation:** Profile and tune the interval.

#### 49. [Architecture] Hardcoded "Start timer" String
- **File:** `DescriptionMarkupFlow.swift`
- **Impact:** A single hardcoded English string was found in the architecture review — overlaps with Standards finding #16.
- **Recommendation:** See finding #16.

#### 50. [Architecture] No Plugin Pattern for New Markup Types
- **File:** `description-editor-bridge.js`
- **Impact:** Adding a new markup type (e.g., temperature, weight) requires changes in 8+ files with no abstraction. Not scalable.
- **Recommendation:** Design a markup plugin pattern for future extensibility.

#### 51. [Architecture] Circular Focus Flow with `suppressIncomingFocus` Band-Aid
- **File:** `YDocRecipeDetailView.swift`
- **Impact:** `suppressIncomingFocus` boolean is used to break a focus loop between SwiftUI and the WebView. Fragile — any new focus event could reintroduce the loop.
- **Recommendation:** Root-cause the focus loop and fix the underlying cause rather than suppressing symptoms.

#### 52. [Architecture] Scalability of Adding Markup Types (8+ files per type)
- **Files:** Multiple
- **Impact:** Each new markup type touches: bridge.js, DescriptionMarkupFlow.swift, YDocRecipeDetailView.swift, DescriptionFormattingBar.swift, the native menu, accessibility identifiers, and tests.
- **Recommendation:** Same as finding #50 — design an extensible markup plugin system.

#### 53. [Standards] Swizzle Lifecycle Concern
- **File:** `Bundle+Language.swift`
- **Impact:** The swizzle for localization is applied globally and never undone. If the app's lifecycle changes, this could cause issues.
- **Recommendation:** Acceptable for current architecture, but document the trade-off.

#### 54. [Business Logic] Floating Point Precision in Ratio
- **File:** `DescriptionMarkupFlow.swift` L101-108
- **Impact:** `Double` division for ratio produces imprecise values (e.g., `0.3333...`). Display uses `toFixed(2)` which rounds acceptably.
- **Recommendation:** Consider rounding ratio to 4 decimal places before sending to JS.

#### 55. [Business Logic] `IngredientEditReorderTableView.swift` Deletion Is Clean
- **File:** `IngredientEditReorderTableView.swift` (deleted)
- **Impact:** Clean deletion, no broken references.
- **Recommendation:** No action needed.

#### 56. [Standards] `escapeHtml` Not Shared Between JS and Swift
- **Files:** `description-editor-bridge.js`, potential Swift HTML escaping
- **Impact:** If Swift code also escapes HTML, the logic should be consistent.
- **Recommendation:** Audit Swift side for HTML escaping needs.

---

## Checklist

- [ ] **Security vulnerabilities** — Debug logging in release, no WebView navigation policy, `javascript:` URLs, no message schema validation
- [x] **Agent debug endpoints removed** — HTTP logging to `127.0.0.1:7258` properly removed
- [ ] **Business logic correctness** — Timer matching non-determinism, fragment rebuild data loss, ingredient round-trip, selection restore
- [ ] **Performance bottlenecks** — Full fragment rebuild, unthrottled selectionchange, CRDT bloat, 18 @State properties
- [ ] **Code follows project standards** — Typography helpers, localization keys, navigation titles, accessibility IDs
- [ ] **Error handling comprehensive** — Silent JS errors, no error propagation chain, no user-facing feedback
- [ ] **Tests adequate** — Round-trip tests exist but missing for edge cases (orphaned refs, concurrent edits, malformed HTML)
- [ ] **Documentation updated** — Specs partially updated, some logic changes undocumented
- [ ] **Architecture appropriate** — God files need splitting, duplicated logic needs consolidation
- [ ] **Deployment concerns** — Debug logging in release, servings cap mismatch between platforms

---

## Recommendation

**Changes Requested** — The branch has solid feature coverage but must address:

1. **Critical:** Timer matching non-determinism (#1) and fragment rebuild data loss (#2) are data corruption risks
2. **High:** Architecture issues (#4, #5, #6) and performance issues (#7, #8) will compound as the codebase grows
3. **High:** Standards violations (#13-#18) should be fixed before merge to prevent normalization of bad patterns

**Suggested approach:** Fix criticals + high-priority findings, then re-review the affected files before merge.
