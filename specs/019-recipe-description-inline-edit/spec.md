# Спецификация: inline-редактирование описания рецепта (Tiptap + нативная панель)

**Ветка**: `019-recipe-description-inline-edit`  
**Дата**: 2026-06-10  
**Статус**: Draft  
**Зависимости**: `002-native-editing`, `004-description-read-only`, `006-description-editor` (мост Yjs), `018-description-editor-richtext` (функциональный паритет)  
**Эталон UX**: mobile stacked в `recipe-scaler-web/recipe-scaler/src/pages/recipe-detail.tsx` — один `isEditMode`, порядок: ингредиенты → инструкции  
**Эталон движка**: `tiptap-recipe-editor.tsx` + `tiptap-menu-bar.tsx`

## Контекст

Сейчас на iOS в режиме Edit ингредиенты правятся **inline** в `YDocRecipeDetailView`, а описание — через **sheet** `DescriptionEditorView` (`contentEditable`, не Tiptap). Это ломает поток «добавил ингредиент → сразу пишу шаги» и не совпадает с мобильным вебом.

В ходе проектирования зафиксировано:

- **один Edit** на весь рецепт (как веб);
- **общий вертикальный скролл** на экране детали;
- **WKWebView + Tiptap** на `Y.XmlFragment('description')` (бинарный паритет с вебом);
- **нативная sticky-панель** форматирования, привязанная к Tiptap через мост (не HTML-toolbar внутри WebView);
- **018** (ссылки, ingredient/timer nodes, таймеры в просмотре) и **LLM-разбор** — в scope, реализация поэтапная;
- отдельный sheet-редактор описания — **снят с целевого UX** (deprecated после внедрения 019).

## Цель

Редактирование инструкций v3 **на том же экране и в том же режиме Edit**, что и ингредиенты, с удобной нативной панелью инструментов и управляемой высотой WebView, с sync и офлайн как в 002/006.

## Пользовательские сценарии

### US1 — Один Edit, порядок как на вебе (P1)

**Дано** v3-рецепт, **когда** пользователь нажимает Edit, **тогда** на одном скролле доступны правка названия/цвета/изображения, сетка ингредиентов и **inline** блок инструкций (без кнопки «открыть редактор» и без отдельного sheet). **Done** в toolbar рецепта завершает весь edit.

**Порядок блоков в Edit (stacked parity):**

1. Изображение (если есть / добавление в edit)  
2. Название + цвет  
3. Чип sync записи  
4. Ингредиенты (`YDocIngredientsEditSection`, порции в сетке)  
5. Заголовок секции инструкций (скроллится с контентом)  
6. Inline Tiptap (`RecipeDescriptionEditorBlock`)

**Просмотр (не edit):** без изменений — `StepsSection` (004), нативный HTML.

### US2 — Печать и форматирование через нативную sticky-панель (P1)

**Когда** фокус в поле описания (Tiptap), **тогда** внизу экрана (над home indicator / клавиатурой) показывается **нативная** панель инструментов; кнопки вызывают команды Tiptap через мост (`editor.chain()…`). **Когда** фокус в поле ингредиента или названия, **тогда** панель **скрыта**.

**Набор кнопок (паритет `tiptap-menu-bar.tsx`, порядок как на вебе):**

1. Заголовок (H1)  
2. Жирное  
3. Выделить фон (highlight)  
4. Нумерованный список  
5. Маркированный список  
6. Разметить выделение как **таймер** (см. [contracts/description-markup-parity.md](./contracts/description-markup-parity.md))  
7. Разметить выделение как **ингредиент** (там же)  
8. **Автораспознавание** (Sparkles / LLM)

Состояние active/disabled — из JS (`selectionState`). Разметка таймера/ингредиента и LLM **не изобретается на iOS**: логика и атрибуты нод = веб-код; UI шагов выбора — нативные sheet вместо Radix dropdown.

### US3 — Высота WebView и длинный текст (P1)

**Когда** текст короткий/средний, **тогда** WebView в режиме **embedded**: внутренний скролл WebView **выключен**, высота frame = `contentHeight` от JS (не меньше `minEmbeddedHeight`), скроллит **родительский** `ScrollView`.

**Когда** `contentHeight` превышает `embeddedMaxHeight` (порог по умолчанию **2000 pt**, уточняется в `research.md` после профилирования), **тогда** блок переходит в режим **focus**: WebView занимает доступную высоту viewport минус sticky-панель (и клавиатура), **внутренний скролл включён**; пользователь остаётся в том же Edit, без второго экрана.

### US4 — Sync, офлайн, remote (P1)

Поведение как 006: локальные правки → yrs `applyUpdate` → debounce ~1 с → `sync_request`; офлайн-очередь 002; при `recipe_updated` — `applyUpdate` в открытый редактор. Sheet с отдельным Cancel/Done для описания не используется.

### US5 — Rich-text паритет (018) (P2, поэтапно)

Ссылки, round-trip XML с ProseMirror, tap по нодам (unlink ingredient, timer popover) — из `018-description-editor-richtext/spec.md`. **Вставка timer/ingredient nodes** описана нормативно в [contracts/description-markup-parity.md](./contracts/description-markup-parity.md) (эталон: `tiptap-recipe-editor.tsx`, `steps-section.tsx`, extension-ноды). iOS: нативные sheet вместо Radix.

### US6 — Запуск таймера из просмотра (P2)

Tap по timer-ноде в `StepsSection` (004) → локальный `TimerManager` — FR-DESC-EDIT-005 / US4 в 018.

### US7 — LLM «разобрать рецепт» (P2)

**Когда** пользователь в Edit нажимает Sparkles на панели, **тогда** поведение = веб `runParseWithLLM` (см. [description-markup-parity.md](./contracts/description-markup-parity.md) § LLM): `POST /api/v1/recipes/{id}/parse`, `stepsText` = `editor.getHTML()` для v3, `apply: true`. **v1/v2** на iOS read-only — кнопка **не показывается**.

### US8 — Legacy v1/v2 (P1)

Редактор описания и панель **недоступны**; баннер 002 без изменений.

## Требования

### FR-019-UI-001 — Без sheet-редактора описания

Удалить из целевого UX: `DescriptionEditorEntrySection` с кнопкой открытия sheet, `showsDescriptionEditor` как основной путь. Код sheet может оставаться временно за feature flag до удаления.

### FR-019-UI-002 — Sticky-панель

- Размещение: `safeAreaInset(edge: .bottom)` (или эквивалент с клавиатурой), **не** внутри `ScrollView`.
- Видимость: `descriptionEditorFocused == true` (события `focus` / `blur` из моста).
- Доступность: подписи из `Localizable.xcstrings`, минимальный размер tap target по HIG.
- WebView: в iOS-сборке Tiptap **без** видимого HTML `TiptapMenuBar` (toolbar только нативный).

### FR-019-UI-003 — Режимы высоты

| Параметр | Значение по умолчанию | Назначение |
|----------|----------------------|------------|
| `minEmbeddedHeight` | 280 pt | Пустое/короткое поле |
| `embeddedMaxHeight` | 2000 pt | Порог перехода embedded → focus |
| `focusMinHeight` | max(320, viewport − sticky − keyboard) | Режим focus |

JS шлёт `contentHeight` при изменении документа/layout; Swift обновляет frame WebView.

### FR-019-ENG-001 — Tiptap bundle

WKWebView загружает bundle с теми же extensions, что веб v3 (StarterKit, Link, Highlight, Collaboration на `description`, TimerNode, IngredientNode, …). Замена или эволюция `Resources/DescriptionEditor/` — см. `plan.md`.

### FR-019-ENG-002 — Мост команд

Контракт: `contracts/description-editor-bridge-v2.md`. Swift → `command`; JS → `selectionState`, `contentHeight`, `focus`, `update`, `ready`.

### FR-019-ENG-003 — Один WebView на сессию Edit

Создание при входе в edit (или при первом фокусе в описании — решение в plan); teardown при выходе из edit / уходе с экрана. Не держать два экземпляра.

### FR-019-ENG-004 — Конкуренция фокуса

При фокусе в Tiptap — снимать фокус с `TextField` ингредиентов/названия (паттерн как `dismissRecipeTitleKeyboard`). При фокусе в ингредиенте — blur редактора описания (опционально soft blur, не теряя черновик).

## Вне scope

- Миграция v1/v2 → v3 на iOS  
- Нативный движок ProseMirror без WebView (spike D — только go/no-go в `research.md`)  
- Кросс-девайс sync таймеров (014)  
- Desktop split-pane веба

## Критерии успеха

- **SC-001**: В Edit пользователь правит ингредиент и без перехода на другой экран правит абзац инструкции; один Done.  
- **SC-002**: Изменение на iOS видно на вебе ≤ 5 с (Wi‑Fi), v3 XmlFragment.  
- **SC-003**: Sticky-панель видна только при фокусе в описании; bold toggles и подсвечивается active.  
- **SC-004**: Рецепт с текстом > `embeddedMaxHeight` открывается в focus без краша/зависания скролла (ручной чеклист + Instruments по желанию).  
- **SC-005**: Офлайн правка описания → веб после reconnect ≤ 10 с.  
- **SC-006** (фаза 018): round-trip сложной разметки без ошибок ProseMirror на вебе.

## Связь с другими спеками

| Спека | Связь |
|-------|--------|
| 006 | Мост Yjs сохраняется; UI sheet deprecated; contentEditable заменяется Tiptap |
| 018 | Функциональные US переносятся в 019 как фазы P2+ |
| 002 | Edit mode, debounce, v3 gate без изменений принципа |

## Риски

| Риск | Митигация |
|------|-----------|
| Гигантский WebView в embedded | `embeddedMaxHeight` + focus |
| Клавиатура перекрывает текст | focus-режим, scrollTo caret (JS postMessage `caretRect` — опционально P2) |
| Размер IPA | esbuild shared с вебом, tree-shake |
| Sticky + ScrollView жесты | панель вне ScrollView (`safeAreaInset`) |

## Артефакты

- [research.md](./research.md) — высота, spike нативного RTE, bundle  
- [plan.md](./plan.md) — фазы реализации  
- [contracts/description-editor-bridge-v2.md](./contracts/description-editor-bridge-v2.md) — мост v2  
- [contracts/description-markup-parity.md](./contracts/description-markup-parity.md) — **панель, таймер, ингредиент, LLM** (эталон веб)  
- [quickstart.md](./quickstart.md) — ручная проверка iOS ↔ web