# Contract — Description editor bridge (Swift ↔ WKWebView)

**Handler**: `window.webkit.messageHandlers.descriptionEditor`  
**JS receive**: `window.__descriptionEditorReceive(payload)`

## Swift → JS

| `type` | Fields | When |
|--------|--------|------|
| `init` | `state: [UInt8]` — full recipe `encodeStateAsUpdate` | After `loaded` |
| `applyUpdate` | `update: [UInt8]` | Remote `recipe_updated` while editor open |

## JS → Swift

| `type` | Fields | When |
|--------|--------|------|
| `loaded` | — | DOM + scripts ready |
| `ready` | `fragmentLength: Int` | Y.Doc applied, editor rendered |
| `update` | `update: [UInt8]` | Local Yjs transaction (not `origin === 'remote'`) |

## Swift side effects

- `update` → `YjsSyncService.applyDescriptionEditorUpdate` → yrs `applyUpdate` + `handleLocalRecipeUpdate` (debounce 1s).
- Editor session registers on `DescriptionEditorBridge` init; remote updates forwarded after `DocumentManager.applyUpdate`.

## Debug launch

```bash
xcrun simctl launch … ru.recipescaler.RecipeScaler \
  -OpenRecipeId=<uuid> -StartDescriptionEdit=1
```

Logs (DEBUG): `description_editor_init`, `description_editor_ready` in `.debug-session.ndjson`.