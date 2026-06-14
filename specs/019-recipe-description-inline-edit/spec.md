# Спецификация: inline-редактирование описания рецепта (Tiptap + нативная панель)

**Ветка**: `019-recipe-description-inline-edit`  
**Дата**: 2026-06-10 (создана), 2026-06-15 (аудит кода)  
**Статус**: 🟢 **Реализовано почти полностью** — inline Tiptap, sticky-панель, sync, timer/ingredient markup (018). Остаток: LLM Sparkles, удаление legacy `DescriptionEditorView`, polish/quickstart.  
**Зависимости**: `002` ✅, `004` ✅, `006` ✅ (superseded), `018` 🟢  
**Эталон UX**: mobile stacked `recipe-detail.tsx`  
**Эталон движка**: `tiptap-recipe-editor.tsx` + `tiptap-menu-bar.tsx`

## Аудит реализации (2026-06-15)

| Требование | Статус | Где в коде |
|------------|--------|------------|
| US1 один Edit, inline instructions | ✅ | `YDocRecipeDetailView` → `RecipeDescriptionEditorBlock`; sheet path **не используется** |
| US2 sticky-панель (H1/bold/highlight/lists/timer/ingredient) | ✅ | `DescriptionFormattingBar` + `safeAreaInset`; `DescriptionEditorBridge.selectionState` |
| US3 высота WebView | ✅ | `contentHeight` → frame; родительский `ScrollView` скроллит (inner focus-scroll **упрощён** — см. ниже) |
| US4 sync / offline / remote | ✅ | `DescriptionEditorBridge` + `applyDescriptionEditorUpdate`; `suspendRecipeRefresh` на edit |
| US5 rich-text 018 (nodes) | ✅ | Native sheets + bridge commands — см. [018](../018-description-editor-richtext/spec.md) |
| US6 timer из просмотра | ✅ | `StepsSection` + `DescriptionTimerPopoverOverlay` |
| US7 LLM Sparkles | ❌ | Кнопка в `DescriptionFormattingBar` (`onParseRecipe`); **не проведена** в `YDocRecipeDetailView` |
| US8 v1/v2 gate | ✅ | `canEnterEditMode` / legacy banner без изменений |
| FR-019-ENG-001 Tiptap bundle | ✅ | `Resources/DescriptionEditor/yjs.bundle.js` + `description-editor-bridge.js` (Tiptap Editor API) |
| FR-019-ENG-002 мост v2 | ✅ | `DescriptionEditorBridge` — `command`, `selectionState`, `contentHeight`, `focus`, `nodeClick` |
| FR-019-UI-001 без sheet | 🟡 | UX без sheet ✅; файл `DescriptionEditorView.swift` **ещё в target** (dead code) |
| FR-019-UI-003 focus mode | 🟡 | `heightMode` в bridge есть; `RecipeDescriptionEditorBlock` всегда `allowsScrolling: false` + полная высота — длинный текст скроллит **родитель**, не inner WebView |

**Решение по высоте (2026-06-15):** вместо переключения embedded/focus с inner scroll — один режим: WebView растёт по `contentHeight`, скролл у `ScrollView` деталки. Порог 2000 pt в bridge остаётся для метрик, UI-переключения focus нет.

## Контекст

Целевой UX **достигнут**: один Edit на `YDocRecipeDetailView`, ингредиенты и инструкции на одном скролле, Tiptap на `Y.XmlFragment('description')`, нативная sticky-панель через bridge v2.

Legacy `DescriptionEditorView` / `DescriptionEditorEntrySection` — **не подключены** к production path; удаление файла — T021.

## Цель

Редактирование инструкций v3 на том же экране и в том же режиме Edit, что и ингредиенты, с нативной панелью, sync и офлайн как в 002/006.

## Пользовательские сценарии

### US1 — Один Edit, порядок как на вебе (P1) ✅

Inline `RecipeDescriptionEditorBlock` в edit; read — `StepsSection`.

### US2 — Sticky-панель (P1) ✅

8 кнопок паритета menu bar (без Sparkles до US7). LLM-кнопка в bar есть, но disabled path (`onParseRecipe == nil`).

### US3 — Высота WebView (P1) ✅ (упрощённо)

`minEmbeddedHeight` 280 pt; `contentHeight` от JS; parent scroll.

### US4 — Sync, офлайн, remote (P1) ✅

Debounced outbound; offline queue 002; remote `applyUpdate` в открытый editor.

### US5 — Rich-text паритет (018) (P2) ✅

См. spec 018.

### US6 — Запуск таймера из просмотра (P2) ✅

### US7 — LLM «разобрать рецепт» (P2) ❌

`POST /api/v1/recipes/{id}/parse` — не подключён из Swift.

### US8 — Legacy v1/v2 (P1) ✅

## Требования

### FR-019-UI-001 — Без sheet-редактора ✅ (код legacy остаётся)

### FR-019-UI-002 — Sticky-панель ✅

### FR-019-UI-003 — Режимы высоты 🟡

Parent-scroll вместо inner focus scroll.

### FR-019-ENG-001 — Tiptap bundle ✅

`Resources/DescriptionEditor/` (не отдельный `TiptapEditor/`).

### FR-019-ENG-002 — Мост команд ✅

### FR-019-ENG-003 — Один WebView на сессию Edit ✅

`RecipeDescriptionEditorBlock.onDisappear` → `teardown()`.

### FR-019-ENG-004 — Конкуренция фокуса ✅

`DescriptionEditorChromeState`, blur при markup sheets.

## Вне scope

- Миграция v1/v2 → v3 на iOS
- Desktop split-pane

## Критерии успеха

- **SC-001**: Edit: ингредиент + инструкции без другого экрана — ✅
- **SC-002**: Sync на веб ≤ 5 с — ✅ (ручной quickstart по желанию)
- **SC-003**: Sticky-панель только при фокусе — ✅
- **SC-004**: Длинный текст без краша — ✅ (parent scroll)
- **SC-005**: Офлайн → веб — ✅
- **SC-006** (018 round-trip): 🟡

## Связь с другими спеками

| Спека | Связь |
|-------|--------|
| 006 | Superseded: Tiptap inline вместо sheet contentEditable |
| 018 | Timer/ingredient/tap — ✅ в коде |
| 002 | Edit mode без изменений принципа |

## Артефакты

- [research.md](./research.md)
- [plan.md](./plan.md)
- [tasks.md](./tasks.md)
- [contracts/description-editor-bridge-v2.md](./contracts/description-editor-bridge-v2.md)
- [contracts/description-markup-parity.md](./contracts/description-markup-parity.md)
- [quickstart.md](./quickstart.md)
