# Спецификация: rich-text паритет редактора описания

**Ветка**: `018-description-editor-richtext`  
**Дата**: 2026-06-03 (создана), 2026-06-15 (аудит кода)  
**Статус**: 🟢 **Реализовано** (2026-06-15) — timer/ingredient nodes, tap-to-start, Tiptap XmlFragment + autolink. Ручной UI вставки ссылки убран из scope (решение 2026-06-15). Остаток: formal round-trip quickstart (SC-004).  
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
| US1 Ссылки (ручная вставка) | ❌ вне scope | Extension `Link` + **autolink** в Tiptap активны. Нативной кнопки «вставить ссылку» нет — убрано из спеки 2026-06-15 (на веб mobile menu bar отдельной кнопки тоже нет). |
| FR-018-001 Тулбар timer/ingredient | ✅ | `DescriptionFormattingBar` + native sheets (`DescriptionMarkupFlow.swift`) |
| FR-018-003 Запуск таймера | ✅ | `startDescriptionTimer(from:)` в `YDocRecipeDetailView`, `DiscoverRecipeView` |
| FR-018-004 Round-trip | 🟡 | XCTest + Node script; SC-004 quickstart — открытый пункт |

**Не сделано / низкий приоритет:**

- Formal closure SC-004 (ручной чеклист iOS edit → web ProseMirror без ошибок на fixture-наборе). Тесты `YrsDescriptionRoundtripTests` + Node script покрывают бинарный round-trip; manual QA matrix остаётся открытым пунктом.

## Контекст

Из **006** перенесено в 018/019. Базовый `contentEditable` **заменён на Tiptap** (не отдельный `Resources/TiptapEditor/` — bundle живёт в `Resources/DescriptionEditor/`).

## Цель

Довести редактирование описания до видимого паритета с вебом по форматированию и custom-нодам, сохранив бинарную совместимость Yjs.

## Пользовательские сценарии

### US1 — Ссылки (P1) — autolink only

**Когда** пользователь вводит URL, **тогда** Tiptap autolink распознаёт его и создаёт `Link` mark в XmlFragment, совместимый с вебом. Ручная вставка ссылки через отдельную UI-кнопку — вне scope v1.

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

Кнопки timer, ingredient на нативной sticky-панели; ссылка — только autolink.

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
- Нативный flow «выделить текст → ввести URL → setLink» (убрано 2026-06-15: на веб mobile menu bar отдельной кнопки ссылки нет, признано избыточным)

## Критерии успеха

- **SC-001**: URL/autolink на iOS кликабелен на вебе после sync — ✅ (autolink)
- **SC-002**: Timer-нода iOS → веб с тем же duration — ✅
- **SC-003**: Tap timer-ноды в просмотре → локальный таймер — ✅
- **SC-004**: Round-trip сложной разметки — 🟡 tests exist, quickstart open

## Артефакты

- [019/contracts/description-markup-parity.md](../019-recipe-description-inline-edit/contracts/description-markup-parity.md) — норматив timer/ingredient/LLM
- [019/contracts/description-editor-bridge-v2.md](../019-recipe-description-inline-edit/contracts/description-editor-bridge-v2.md) — мост v2
- `RecipeScalerNativeTests/YrsDescriptionRoundtripTests.swift`
- `scripts/test-yjs-description-roundtrip.mjs`
