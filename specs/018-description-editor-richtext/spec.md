# Спецификация: rich-text паритет редактора описания

**Ветка**: `018-description-editor-richtext`  
**Дата**: 2026-06-03 (создана), 2026-06-15 (аудит кода)  
**Статус**: 🟢 **Реализовано почти полностью** — timer/ingredient nodes, tap-to-start, Tiptap XmlFragment. Остаток: ручной UI «вставить ссылку» + formal round-trip quickstart.  
**Зависимости**: `019` (inline + нативная панель) ✅, `006` (мост Yjs) ✅, `004` (read-only рендер) ✅  
**Эталон**: Tiptap в `recipe-scaler-web/recipe-scaler` `recipe-detail`, custom-ноды ingredient/timer

## Аудит реализации (2026-06-15)

Реализовано в связке с **019**: WKWebView + **настоящий Tiptap** (`Resources/DescriptionEditor/yjs.bundle.js`, `description-editor-bridge.js` — `Editor`, `StarterKit`, `Link`, `Highlight`, `TimerNode`, `IngredientNode`, `Collaboration` на `Y.XmlFragment`).

| Требование | Статус | Где в коде |
|------------|--------|------------|
| US2 Ingredient node (вставка) | ✅ | `markAsIngredient` в bridge; `DescriptionIngredientMarkupSheet`; `YDocRecipeDetailView.applyDescriptionIngredientMarkup` |
| US3 Timer node (вставка) | ✅ | `markAsTimer` в bridge; `DescriptionTimerTypeSheet`; rename/unlink/update через `DescriptionTimerNodeFlowSheet` / `DescriptionIngredientNodeFlowSheet` |
| US4 Запуск таймера из описания | ✅ | Read: `StepsSection` + `DescriptionTimerPopoverOverlay` → `TimerManager`; Edit: `handleDescriptionNodeClick` → `DescriptionTimerNodeFlowSheet.onStart` |
| US5 XML-паритет (базовый) | 🟡 | `YrsDescriptionRoundtripTests` + `scripts/test-yjs-description-roundtrip.mjs`; полный iOS↔web quickstart не зафиксирован в spec |
| US1 Ссылки (ручная вставка) | 🟡 | Extension `Link` + **autolink** в Tiptap; **нет** кнопки/команды `setLink` на нативной панели (на веб mobile menu bar отдельной кнопки «ссылка» тоже нет — см. `description-markup-parity.md`) |
| FR-018-001 Тулбар timer/ingredient | ✅ | `DescriptionFormattingBar` + native sheets (`DescriptionMarkupFlow.swift`) |
| FR-018-003 Запуск таймера | ✅ | `startDescriptionTimer(from:)` в `YDocRecipeDetailView`, `DiscoverRecipeView` |
| FR-018-004 Round-trip | 🟡 | XCTest + Node script; SC-004 quickstart — открытый пункт |

**Не сделано / низкий приоритет:**

- Нативный flow «выделить текст → ввести URL → setLink» (если понадобится сверх autolink).
- Formal closure SC-004 (ручной чеклист iOS edit → web ProseMirror без ошибок на fixture-наборе).

## Контекст

Из **006** перенесено в 018/019. Базовый `contentEditable` **заменён на Tiptap** (не отдельный `Resources/TiptapEditor/` — bundle живёт в `Resources/DescriptionEditor/`).

## Цель

Довести редактирование описания до видимого паритета с вебом по форматированию и custom-нодам, сохранив бинарную совместимость Yjs.

## Пользовательские сценарии

### US1 — Ссылки (P1)

**Когда** пользователь вводит URL или autolink срабатывает на typed URL, **тогда** mark `Link` в XmlFragment совместим с вебом. **Ручная** вставка ссылки через UI — 🟡 не реализована (autolink ✅).

### US2 — Ingredient node (P2) ✅

**Когда** пользователь вставляет ссылку на ингредиент, **тогда** нода с `data-ingredient-id` и атрибутами как на вебе; read-рендер (004) показывает масштабированное количество.

### US3 — Timer node (P2) ✅

**Когда** пользователь вставляет таймер, **тогда** нода с `duration`/`type` как на вебе.

### US4 — Запуск таймера из описания (P1) ✅

**Дано** режим просмотра или редактирования, **когда** tap по timer-ноде, **тогда** создаётся локальный таймер (`TimerManager`).

### US5 — XML-паритет (P1) 🟡

**Когда** на iOS создаётся сложная разметка, **тогда** веб открывает её без ошибок ProseMirror — покрыто тестами частично; нужен formal quickstart.

## Требования

### FR-018-001 — Тулбар ✅

Кнопки timer, ingredient на нативной sticky-панели; ссылка — autolink only.

### FR-018-002 — Атрибуты нод ✅

Соответствие схеме веба; мутации через Tiptap bridge → yrs.

### FR-018-003 — Запуск таймера ✅

Timer-ноды кликабельны в `StepsSection` и в inline editor.

### FR-018-004 — Совместимость 🟡

`YrsDescriptionRoundtripTests`; companion Node script.

## Вне scope

- Полная замена WKWebView нативным RTE
- Кросс-девайс sync таймеров (014) — done отдельно
- Миграция v1/v2 → v3

## Критерии успеха

- **SC-001**: URL/autolink на iOS кликабелен на вебе после sync — 🟡 autolink OK; manual link UI N/A
- **SC-002**: Timer-нода iOS → веб с тем же duration — ✅
- **SC-003**: Tap timer-ноды в просмотре → локальный таймер — ✅
- **SC-004**: Round-trip сложной разметки — 🟡 tests exist, quickstart open

## Артефакты

- [019/contracts/description-markup-parity.md](../019-recipe-description-inline-edit/contracts/description-markup-parity.md) — норматив timer/ingredient/LLM
- [019/contracts/description-editor-bridge-v2.md](../019-recipe-description-inline-edit/contracts/description-editor-bridge-v2.md) — мост v2
- `RecipeScalerNativeTests/YrsDescriptionRoundtripTests.swift`
- `scripts/test-yjs-description-roundtrip.mjs`
