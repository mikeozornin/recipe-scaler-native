# План реализации: 019 inline description editor

**Ветка**: `019-recipe-description-inline-edit` | **Дата**: 2026-06-10 | **Спека**: [spec.md](./spec.md)

## Кратко

Заменить sheet + contentEditable на **inline Tiptap** в `YDocRecipeDetailView`, **нативную sticky-панель** и режимы высоты embedded/focus. Мост Yjs из 006 сохранить, расширить [contracts/description-editor-bridge-v2.md](./contracts/description-editor-bridge-v2.md).

## Проверка конституции

| Gate | Статус |
|------|--------|
| Native UI | ✅ SwiftUI shell; WKWebView только canvas описания |
| CRDT / sync | ✅ XmlFragment через applyUpdate |
| Паритет веб stacked | ✅ Один Edit, порядок блоков |
| i18n | ✅ Ключи панели в `Localizable.xcstrings` |

## Фазы

### Phase 0 — Подготовка

- [ ] Tiptap esbuild target `Resources/TiptapEditor/` (или рефактор `DescriptionEditor/`)
- [ ] JS: экспорт `window.__descriptionEditor` с `editor`, обработка `command`
- [ ] Обновить `DescriptionEditorBridge` + координатор под v2 сообщения
- [ ] Feature flag `inlineDescriptionEditor` (опционально) для отката sheet

### Phase 1 — Inline MVP (US1, US3, US4)

- [ ] `RecipeDescriptionEditorBlock` в `YDocRecipeDetailView` вместо `DescriptionEditorEntrySection`
- [ ] Убрать основной путь `showsDescriptionEditor` sheet (оставить dead code за flag до Phase 4)
- [ ] `contentHeight` + embedded mode (`embeddedMaxHeight` = 2000)
- [ ] Focus mode при превышении порога
- [ ] Remote `applyUpdate` пока edit открыт
- [ ] Build + quickstart SC-001, SC-002, SC-005

### Phase 2 — Нативная sticky-панель (US2)

- [ ] `DescriptionFormattingBar` + `safeAreaInset(edge: .bottom)`
- [ ] `focus` / `blur` / `selectionState` из WebView
- [ ] Команды: H1, bold, highlight, ordered/bullet lists
- [ ] SC-003

### Phase 3 — Tiptap parity core (018 P1)

- [ ] Link: нативный alert/sheet URL → `setLink`
- [ ] Скрыть/не собирать web `TiptapMenuBar` в iOS bundle
- [ ] Round-trip простой разметки (quickstart)

### Phase 4 — Nodes + LLM (018 P2, US7)

- [ ] Реализовать [contracts/description-markup-parity.md](./contracts/description-markup-parity.md) (timer + ingredient sheets + LLM API)
- [ ] Timer tap в `StepsSection` → `TimerManager`
- [ ] LLM Sparkles: Swift + API parity `runParseWithLLM`, только v3 editable
- [ ] Удалить sheet `DescriptionEditorView` и HTML toolbar
- [ ] SC-006 выборочно

### Phase 5 — Полировка

- [ ] `caretRect` + scroll к каретке (если нужно после QA)
- [ ] Instruments: память WebView на длинном рецепте
- [ ] Обновить `docs/ARCHITECTURE.md`, `006`/`018` статусы, `llm/DECISIONS.md` по запросу

## Компоненты (целевые пути)

```text
RecipeScalerNative/Views/
├── YDocRecipeDetailView.swift          # inline block, safeAreaInset bar
├── RecipeDescriptionEditorBlock.swift    # NEW — WebView + height mode
├── DescriptionFormattingBar.swift      # NEW — sticky toolbar
├── DescriptionEditorWebView.swift      # extend: height, no full-screen only
├── DescriptionEditorView.swift         # DEPRECATE → remove Phase 4

RecipeScalerNative/Services/
├── DescriptionEditorBridge.swift       # v2 commands + selectionState

RecipeScalerNative/Resources/TiptapEditor/  # NEW or rename
├── tiptap-recipe-ios.html
└── tiptap-recipe-ios.bundle.js
```

## Тестирование

- XCTest: bridge command whitelist (unit на парсинг `selectionState` JSON)
- Ручное: [quickstart.md](./quickstart.md)
- `rtk xcodebuild -scheme RecipeScalerNative build` после каждой фазы

## Зависимости от веба

- `tiptap-recipe-editor.tsx`, `tiptap-menu-bar.tsx` — эталон команд
- `recipe-detail.tsx` stacked порядок секций
- LLM: повторить контракт `runParseWithLLM` (прочитать endpoint при Phase 4)