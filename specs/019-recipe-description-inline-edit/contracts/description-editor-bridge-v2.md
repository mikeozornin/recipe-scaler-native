# Contract — Description editor bridge v2 (Swift ↔ WKWebView, Tiptap)

**Версия**: 2.0  
**Заменяет для 019**: расширяет [006 description-editor-bridge.md](../../006-description-editor/contracts/description-editor-bridge.md); сообщения `init` / `applyUpdate` / `update` / `loaded` / `ready` **совместимы** с v1.

**Handler**: `window.webkit.messageHandlers.descriptionEditor`  
**JS receive**: `window.__descriptionEditorReceive(payload)`

## Swift → JS

### Существующие (v1)

| `type` | Fields | When |
|--------|--------|------|
| `init` | `state: [UInt8]` — full recipe `encodeStateAsUpdate` | После `loaded`, редактор Tiptap создан |
| `applyUpdate` | `update: [UInt8]` | Remote `recipe_updated` пока edit-сессия активна |

### Новые (v2)

| `type` | Fields | When |
|--------|--------|------|
| `command` | `name: String`, `args: [String: Any]?` | Tap на нативной sticky-панели |

#### Whitelist `command.name`

Каждая команда выполняется в JS как `editor.chain().focus()…run()` (или ref-методы Tiptap), только если `editor` в состоянии `ready`.

| `name` | `args` | JS (эквивалент веба) |
|--------|--------|----------------------|
| `toggleBold` | — | `toggleBold()` |
| `toggleHeading1` | — | `toggleHeading({ level: 1 })` |
| `toggleHighlight` | — | `toggleHighlight()` |
| `toggleBulletList` | — | `toggleBulletList()` |
| `toggleOrderedList` | — | `toggleOrderedList()` |
| `toggleItalic` | — | `toggleItalic()` (если extension включён) |
| `focus` | — | `editor.commands.focus()` |
| `blur` | — | `editor.commands.blur()` |
| `markAsIngredient` | `ingredientId`, `originalAmount?`, `ratio?` | как `TiptapRecipeEditorRef.markAsIngredient` |
| `markAsTimer` | `type`, `value`, `duration`, `timerId`, `name?` | как `markAsTimer` |
| `undo` / `redo` | — | опционально P2 |

**Запрещено:** произвольный JS из Swift; неизвестные `name` игнорируются + log в DEBUG.

## JS → Swift

### Существующие (v1)

| `type` | Fields | When |
|--------|--------|------|
| `loaded` | — | DOM + scripts ready |
| `ready` | `fragmentLength: Int` | Tiptap + Y.Doc applied |
| `update` | `update: [UInt8]` | Local Yjs transaction (`origin !== 'remote'`) |

### Новые (v2)

| `type` | Fields | When |
|--------|--------|------|
| `focus` | — | Tiptap получил фокус |
| `blur` | — | Tiptap потерял фокус |
| `contentHeight` | `height: Double` (pt, CSS px × scale если нужно) | После `update`, resize editor, init |
| `selectionState` | см. ниже | `selectionUpdate`, `transaction` (throttle ≤ 60 ms) |
| `error` | `message: String` | Ошибка инициализации Tiptap |

### `selectionState` payload

```json
{
  "bold": true,
  "heading1": false,
  "highlight": false,
  "bulletList": false,
  "orderedList": false,
  "link": false,
  "canBold": true,
  "canHeading1": true,
  "canHighlight": true,
  "canBulletList": true,
  "canOrderedList": true,
  "canLink": true,
  "hasSelection": true
}
```

Поля `can*` — из `editor.can().toggleBold()` и т.д.; `*` active — из `editor.isActive(…)`.

### Опционально P2

| `type` | Fields | When |
|--------|--------|------|
| `caretRect` | `y`, `height` (в координатах WebView) | Скролл родителя к каретке при клавиатуре |

## Swift side effects

- `update` → `YjsSyncService.applyDescriptionEditorUpdate` → debounce 1 s (без изменений 006).
- `focus` / `blur` → UI: показать/скрыть `DescriptionFormattingBar`.
- `contentHeight` + режим embedded/focus → обновить constraint/frame `WKWebView`.
- `selectionState` → обновить enabled/highlight кнопок панели.

## LLM (US7)

Не через WebView postMessage: кнопка Sparkles на **нативной** панели вызывает Swift `runParseWithLLM` (контракт API — отдельный документ / веб `recipe-detail.tsx`). После успеха — full или partial `applyUpdate` / reload recipe state; WebView получает `applyUpdate` или повторный `init` по политике plan.md.

## Ingredient / timer pickers

Полный flow (парсинг числа, `duration`, фильтр списка, ratio 100% / N%, attrs нод): **[description-markup-parity.md](./description-markup-parity.md)**.

Кратко:

1. Tap на нативной панели → Swift читает `selectionState.hasSelection` / `selectedText`.  
2. Таймер → sheet «часы / минуты / секунды» → `markAsTimer`.  
3. Ингредиент → sheet списка → при несовпадении чисел sheet ratio → `markAsIngredient`.  
4. JS не дублирует бизнес-логику ratio — только вставка по args (как `tiptap-recipe-editor.tsx`).

## Debug

```bash
xcrun simctl launch … ru.recipescaler.RecipeScaler \
  -OpenRecipeId=<uuid> -StartInEditMode=1
```

Фокус в описании: tap в WebView; sticky-панель должна появиться без `-StartDescriptionEdit` (sheet deprecated).

Логи (DEBUG): `description_editor_focus`, `description_editor_content_height`, `description_editor_command` в `.debug-session.ndjson`.