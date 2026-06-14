# Задачи: 019 inline description editor

**Вход**: `/specs/019-recipe-description-inline-edit/`

**Аудит**: 2026-06-15 — статусы синхронизированы с кодом.

**Тесты**: XCTest bridge JSON — T023 открыт; сборка обязательна после каждой фазы.

## Формат: `[ID] [P?] [Story] Описание`

---

## Фаза 1: Setup

- [x] T001 Создать ветку `019-recipe-description-inline-edit`, обновить `.specify/feature.json`
- [x] T002 [P] Расширить `description-editor-bridge.js` — v2: `configure`, `command`, `contentHeight`, `focus`/`blur`, `selectionState`
- [x] T003 [P] Обновить `description-editor.html` — режим `inline-embedded` (без web toolbar)
- [x] T004 Расширить `DescriptionEditorBridge.swift` + `DescriptionEditorWebView.swift` под v2

**Контрольная точка**: мост шлёт `contentHeight` и `focus`; Swift шлёт `command`

---

## Фаза 2: Foundational

- [x] T005 Создать `RecipeScalerNative/Views/DescriptionFormattingBar.swift` — 8 кнопок паритета menu bar
- [x] T006 Создать `RecipeScalerNative/Views/RecipeDescriptionEditorBlock.swift` — embedded высота (parent scroll)
- [x] T007 [P] Ключи i18n `editor.*` в `Localizable.xcstrings` (ru/en)
- [x] T008 Добавить Swift-файлы в `RecipeScalerNative.xcodeproj/project.pbxproj`

---

## Фаза 3: US1 — Inline в одном Edit (P1) 🎯 MVP

- [x] T009 [US1] `YDocRecipeDetailView.swift` — `RecipeDescriptionEditorBlock` вместо `DescriptionEditorEntrySection` + sheet
- [x] T010 [US1] Debug `-StartDescriptionEdit` — фокус inline, не sheet
- [x] T011 [US1] `rtk xcodebuild` build PASS

**Контрольная точка**: SC-001 quickstart

---

## Фаза 4: US2 — Sticky-панель (P1)

- [x] T012 [US2] `safeAreaInset(edge: .bottom)` + `DescriptionFormattingBar` при `bridge.isFocused`
- [x] T013 [US2] Команды H1/bold/highlight/lists через мост; timer/ingredient через native sheets
- [ ] T014 [US2] SC-003 quickstart (ручная фиксация)

---

## Фаза 5: US3–US4 — Высота + sync (P1)

- [x] T015 [US3] `contentHeight` + parent `ScrollView` (упрощение вместо inner focus scroll)
- [x] T016 [US4] Remote `applyUpdate` при edit без sheet

---

## Фаза 6: Tiptap bundle + links (018)

- [x] T017 Tiptap в `Resources/DescriptionEditor/yjs.bundle.js` + `description-editor-bridge.js` (Editor API, не contentEditable)
- [ ] T018 [P] Link: manual `setLink` UI (autolink через Link extension ✅; кнопка на панели — опционально)

---

## Фаза 7: Nodes + LLM

- [x] T019 [US5] Timer/ingredient native sheets — `DescriptionMarkupFlow.swift`, bridge `markAsTimer`/`markAsIngredient`, node click flows
- [ ] T020 [US7] LLM `POST /api/v1/recipes/{id}/parse` — провести `onParseRecipe` из `YDocRecipeDetailView`
- [ ] T021 Удалить `DescriptionEditorView.swift` + `DescriptionEditorEntrySection` из target (dead code, не в navigation path)

---

## Фаза 8: Polish

- [ ] T022 Обновить `docs/ARCHITECTURE.md`, статусы 006/018/019 в заголовках спек
- [ ] T023 [P] XCTest парсинг `selectionState` JSON
