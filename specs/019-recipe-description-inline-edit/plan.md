# План реализации: 019 inline description editor

**Ветка**: `019-recipe-description-inline-edit` | **Дата**: 2026-06-10 | **Аудит**: 2026-06-15 | **Спека**: [spec.md](./spec.md)

## Кратко

Inline **Tiptap** в `YDocRecipeDetailView`, **нативная sticky-панель**, parent-scroll по `contentHeight`. Sheet + contentEditable **сняты с production path**; файл sheet — dead code до T021.

## Проверка конституции

| Gate | Статус |
|------|--------|
| Native UI | ✅ SwiftUI shell; WKWebView только canvas описания |
| CRDT / sync | ✅ XmlFragment через applyUpdate |
| Паритет веб stacked | ✅ Один Edit, порядок блоков |
| i18n | ✅ Ключи `editor.*`, `llm.parse-recipe` |

## Фазы

### Phase 0 — Подготовка ✅

- [x] Tiptap bundle `Resources/DescriptionEditor/` (`yjs.bundle.js`, `description-editor-bridge.js`)
- [x] JS: `Editor` + `runCommand` / `selectionState` / `nodeClick`
- [x] `DescriptionEditorBridge` v2

### Phase 1 — Inline MVP (US1, US3, US4) ✅

- [x] `RecipeDescriptionEditorBlock` в `YDocRecipeDetailView`
- [x] Sheet path не используется в production
- [x] `contentHeight` + parent scroll
- [x] Remote `applyUpdate` при edit

### Phase 2 — Нативная sticky-панель (US2) ✅

- [x] `DescriptionFormattingBar` + `safeAreaInset(edge: .bottom)`
- [x] `focus` / `blur` / `selectionState`
- [x] H1, bold, highlight, ordered/bullet lists
- [x] SC-003 quickstart formal (подтверждено 2026-06-15)

### Phase 3 — Tiptap parity core (018 P1) 🟡

- [x] Tiptap extensions: Link (autolink), Highlight, TimerNode, IngredientNode
- [x] Web toolbar не показывается (inline-embedded HTML)
- [x] Manual setLink UI — вне scope (убрано 2026-06-15; на веб mobile menu bar отдельной кнопки тоже нет)
- [ ] Round-trip quickstart SC-006

### Phase 4 — Nodes + LLM (018 P2, US7) 🟡

- [x] [description-markup-parity.md](./contracts/description-markup-parity.md) — timer + ingredient sheets + edit/read node menus
- [x] Timer tap в `StepsSection` → `TimerManager`
- [ ] LLM Sparkles: Swift + API `runParseWithLLM`
- [ ] Удалить `DescriptionEditorView.swift`

### Phase 5 — Полировка ⏳

- [ ] `caretRect` + scroll к каретке (если нужно после QA)
- [ ] XCTest `selectionState` JSON
- [ ] Обновить `docs/ARCHITECTURE.md`, статусы 006/018

## Компоненты (фактические пути)

```text
RecipeScalerNative/Views/
├── YDocRecipeDetailView.swift          # inline block, safeAreaInset bar, markup sheets
├── RecipeDescriptionEditorBlock.swift  # WebView + height
├── DescriptionFormattingBar.swift      # sticky toolbar
├── DescriptionMarkupFlow.swift         # timer/ingredient sheets + node menus
├── DescriptionEditorWebView.swift
├── DescriptionEditorBridge.swift       # v2
├── DescriptionEditorView.swift         # DEAD CODE → remove T021

RecipeScalerNative/Resources/DescriptionEditor/
├── description-editor.html
├── description-editor-bridge.js        # Tiptap Editor
└── yjs.bundle.js
```

## Оставшийся объём (оценка)

| Задача | Effort |
|--------|--------|
| T020 LLM parse API | M |
| T021 удалить legacy sheet view | S |
| T018 manual link UI | S (optional) |
| T014/T022/T023 polish | S |
