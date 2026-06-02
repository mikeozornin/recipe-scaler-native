# Research — 006 Description Editor

**Date**: 2026-06-02  
**Decision**: WKWebView + embedded **Yjs 13.6.30** (bundled IIFE) with a **minimal contenteditable** bridge, not full Tiptap in v1.

## Options

| Option | Pros | Cons |
|--------|------|------|
| WKWebView + web Tiptap bundle | Full web parity, Collaboration on `XmlFragment` | ~500KB+ JS; custom nodes; build pipeline |
| yrs direct XmlFragment write | No WebView | No stable write API for ProseMirror trees (004 read-only) |
| Minimal WKWebView + Yjs | Binary-compatible updates via `applyUpdate`; debounced sync reuses 002 | Formatting parity incomplete until Tiptap bundle |

## Chosen (MVP)

- **WKWebView** loads `DescriptionEditor/description-editor.html` + `yjs.bundle.js` (~84KB) + `description-editor-bridge.js`.
- Swift holds authoritative **yrs** `Y.Doc`; JS holds a replica for editing `description` fragment.
- **Swift → JS**: full doc state on `init`; incremental `applyUpdate` on `recipe_updated`.
- **JS → Swift**: incremental updates → `DocumentManager.applyDescriptionEditorUpdate` → `UpdateDebouncer` (~1s) → `sync_request`.
- **UI**: sheet from `YDocRecipeDetailView` edit mode; read-only path unchanged (`StepsSection` / 004).

## Follow-up

- Replace contenteditable converter with **Tiptap + Collaboration** (same extensions as `tiptap-recipe-editor.tsx`).
- Ingredient/timer node insertion toolbar (US3).
- Share esbuild script with web repo for bundle size control.