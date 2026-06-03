# Спецификация: редактирование описания рецепта (rich text)

**Ветка**: `006-description-editor`  
**Дата**: 2026-06-02  
**Статус**: 🟡 Частично реализовано (аудит 2026-06-03) — базовый rich-text MVP. Остаток → [018-description-editor-richtext](../018-description-editor-richtext/spec.md)  
**Зависимости**: `004-description-read-only` (чтение v3), `002-native-editing` (sync write)  
**Эталон веба**: `recipe-scaler-web/recipe-scaler` — Tiptap в `recipe-detail`, `Y.XmlFragment('description')`

## Аудит реализации (2026-06-03)

Реализовано: `DescriptionEditorView` + `DescriptionEditorWebView` (WKWebView) + `DescriptionEditorBridge` + bundle `Resources/DescriptionEditor/` (`description-editor.html`, `yjs.bundle.js`, `description-editor-bridge.js`). Редактор — `contentEditable` с мостом в `Y.XmlFragment` через yjs.bundle (US1, US4 offline-очередь, sync через `applyDescriptionEditorUpdate`).

| Требование | Статус |
|------------|--------|
| US1 открыть редактор | ✅ |
| US2 bold/italic/heading/список | 🟡 есть bold/italic/H1/bullet; **нет ссылок** |
| US2 sync на веб | ✅ через мост + debounce |
| US3 ingredient / timer nodes (вставка) | ❌ только CSS-рендер, вставка не реализована |
| US4 офлайн | ✅ |
| US5 remote edit (`applyRemoteUpdate`) | ✅ подключено |
| FR-DESC-EDIT-005 запуск таймера из описания | ❌ |
| Настоящий Tiptap/ProseMirror | ❌ это `contentEditable`, не Tiptap |

Не сделано → перенесено в **018-description-editor-richtext**: ссылки, вставка ingredient/timer-нод, запуск таймеров из описания, проверка XML-паритета с Tiptap.

## Контекст

На вебе инструкции v3 — **Tiptap / ProseMirror** в `Y.XmlFragment('description')` с custom-нодами: ссылки на ингредиенты, таймеры, форматирование.

iOS после **004** показывает описание **только для чтения** (yrs → HTML). Пользователь не может править шаги на телефоне — критичный разрыв с мобильным вебом.

## Цель

Редактирование описания v3 на iOS с **бинарной совместимостью** Yjs 13.6.30 и видимым паритетом с вебом после sync.

## Пользовательские сценарии

### US1 — Открыть редактор (P1)

**Дано** v3-рецепт в режиме редактирования полей (002), **когда** пользователь открывает блок «Instructions», **тогда** открывается полноэкранный или sheet-редактор rich text (не plain `TextEditor`).

### US2 — Форматирование и структура (P1)

**Когда** пользователь применяет bold, italic, заголовки, списки, ссылки, **тогда** изменения попадают в `XmlFragment` и через debounced `sync_request` видны на вебе ≤ 5 с.

### US3 — Ingredient / timer nodes (P2)

**Когда** пользователь вставляет ссылку на ингредиент или таймер, **тогда** в разметке есть те же атрибуты, что веб (`data-ingredient-id`, duration, type и т.д. — см. `docs/YJS-SCHEMA.md` и веб-ноды).

### US4 — Офлайн (P1)

**Дано** офлайн, **когда** пользователь редактирует описание, **тогда** правки в локальном Y.Doc + офлайн-очередь; при reconnect — merge без диалога выбора версии.

### US5 — Remote edit (P2)

**Дано** открыт редактор, **когда** веб меняет описание, **тогда** iOS подтягивает update (observer → bridge) без потери курсора где возможно; при конфликте — CRDT merge (как веб).

### US6 — v1/v2 и legacy (P1)

**Дано** v1/v2, **тогда** редактор описания **недоступен** (как 002); баннер legacy.

## Требования

### FR-DESC-EDIT-001 — Технология редактора

- **Предпочтительно**: `WKWebView` + тот же (или урезанный) Tiptap bundle, что веб, с мостом `yrs XmlFragment ↔ JS Y.XmlFragment`.
- **Альтернатива** (только после `research.md`): нативный редактор, если доказана запись совместимого ProseMirror XML без WKWebView.

### FR-DESC-EDIT-002 — Запись в Y.Doc

Мутации только через yrs write-транзакции / applyUpdate от моста; **не** REST для тела описания.

### FR-DESC-EDIT-003 — Debounce и sync

Тот же debounce ~1 с, что 002; один документ `{userId}:recipe:{recipeId}`.

### FR-DESC-EDIT-004 — Режимы UI

- Просмотр (004): нативный `StepsSection` / `RecipeDescriptionView`.
- Редактирование: отдельный экран; выход с предупреждением при несохранённой локальной очереди (если sync в полёте).

### FR-DESC-EDIT-005 — Запуск таймеров из описания

В режиме просмотра: tap по timer node → создание локального таймера (`TimerManager`), паритет с веб mobile. Детали server push — `014-timers-sync`.

### FR-DESC-EDIT-006 — Производительность

Холодный старт редактора < 500 ms после открытия (нативный PRD §8).

## Вне scope

- Миграция v1/v2 → v3 на iOS
- Редактирование описания без v3
- PDF, импорт

## Критерии успеха

- **SC-001**: Изменение абзаца на iOS → тот же текст на вебе ≤ 5 с (Wi‑Fi).
- **SC-002**: Вставка timer node на iOS → веб показывает таймер с тем же duration.
- **SC-003**: Офлайн правка → веб после reconnect ≤ 10 с.
- **SC-004**: Одновременное редактирование iOS + web — без потери данных в 95% ручных прогонов.

## Артефакты (до кода)

- `research.md` — выбор WKWebView vs native, размер bundle, API yrs XmlFragment write
- `contracts/description-editor-bridge.md` — JS ↔ Swift сообщения
- `quickstart.md` — iOS ↔ web checklist

## Риски

| Риск | Митигация |
|------|-----------|
| yrs XmlFragment write API | Мост через applyUpdate из JS Yjs |
| Размер Tiptap в IPA | Lazy load, shared chunk с вебом где возможно |
| WKWebView memory | Один экземпляр редактора, dismiss при уходе |