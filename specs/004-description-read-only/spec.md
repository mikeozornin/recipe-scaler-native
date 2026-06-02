# Спецификация: просмотр описания рецепта (read-only)

**Ветка**: `004-description-read-only`  
**Дата**: 2026-06-02  
**Статус**: Verified (simulator 2026-06-02)  
**Связано**: Phase 3 (`002-native-editing`), схема `docs/YJS-SCHEMA.md`  
**Следующая фаза**: `005-description-editor` — редактирование (WKWebView + Tiptap или нативный редактор)

## Контекст

На iOS описание **v1/v2** уже читается из `Y.Map('recipe')` (string / `Y.Text`) и показывается в `StepsSection` как HTML.

Для **v3** описание живёт в top-level `Y.XmlFragment('description')` (Tiptap / ProseMirror). Сейчас `DocumentManager.readDescription` для v3 возвращает `nil` — блок «Instructions» на деталке v3 пустой, хотя на вебе текст есть.

Цель этой фичи: **только просмотр** инструкций на детальном экране, без редактирования и **без** WKWebView / Tiptap bundle.

## Пользовательские сценарии

### US1 — v3 рецепт с описанием (P1)

**Как** пользователь, **я хочу** видеть шаги приготовления на экране деталей v3-рецепта, **чтобы** готовить без веб-клиента.

**Приёмка**:

1. **Дано** v3-рецепт с непустым `XmlFragment('description')`, **когда** открываю детали онлайн или офлайн (после sync), **тогда** секция «Instructions» показывает текст/разметку.
2. **Дано** тот же рецепт на вебе, **когда** сравниваю с iOS, **тогда** абзацы, заголовки и списки читаемы; таймеры и ссылки на ингредиенты — в упрощённом виде (см. FR-DESC-004).

### US2 — v1/v2 без регрессии (P1)

**Приёмка**: поведение v1/v2 не меняется — тот же `StepsSection`, те же данные из map.

### US3 — Пустое / отсутствующее описание (P2)

**Приёмка**:

1. **Дано** пустой fragment и `hasSteps == false`, **тогда** секция «Instructions» не показывается.
2. **Дано** `hasSteps == true`, но конвертация дала пустую строку, **тогда** опционально короткий placeholder (i18n) — не обязателен в MVP.

## Требования

### FR-DESC-001 — Источники по версии

| Версия | Источник | Действие |
|--------|----------|----------|
| v1 | `recipeMap.description` string | как сейчас |
| v2 | `recipeMap.description` `Y.Text` | как сейчас |
| v3 | `doc.getXmlFragment('description')` | конвертация в HTML для UI |

### FR-DESC-002 — Нативное чтение v3

Приложение ДОЛЖНО извлекать содержимое `XmlFragment` через **yrs C API** (`yxmlfragment`, `yxmlelem_*`, `yxmltext_*`), без Tiptap и без WKWebView.

### FR-DESC-003 — Отображение UI

- Использовать существующий `StepsSection(htmlContent:)` (HTML → `AttributedString`).
- Секция на `YDocRecipeDetailView` — только когда `description` непустое после чтения.
- Режим редактирования полей рецепта **не** открывает редактор описания.

### FR-DESC-004 — Упрощённый рендер custom-нод

Паритет с web `extractHtmlFromXmlFragment` **не обязателен** в этой фазе. Минимум:

| Tiptap-нода | iOS read-only |
|-------------|----------------|
| `paragraph`, `heading`, списки, `blockquote`, `codeBlock` | HTML-теги (`p`, `h1`–`h6`, `ul`/`ol`/`li`, …) |
| `hardBreak` | `<br/>` |
| `timer` | текст длительности / inner text |
| `ingredient` | масштабированное количество + имя из `recipe.ingredients` по `data-ingredient-id` |
| неизвестный тег | рекурсивно дети, без падения |

### FR-DESC-005 — Синхронизация

При обновлении recipe document с веба (observer / `recipe_updated`) описание на iOS ДОЛЖНО обновляться так же, как остальные поля (перечитать `readRecipeData`).

### FR-DESC-006 — Офлайн

После загрузки snapshot рецепта из SQLite описание v3 ДОЛЖНО отображаться офлайн (данные уже в Y.Doc).

## Вне scope

- Редактирование описания (любая версия).
- WKWebView, Tiptap bundle, `yxmlfragment` write API.
- Полный WYSIWYG-паритет с вебом (подсветка, сложные embed, точные стили).
- Запись `description` в офлайн-очередь.

## Критерии приёмки

1. v3-рецепт с шагами на вебе → на iOS видна секция Instructions.
2. v1/v2 — без регрессии.
3. Офлайн после sync — описание v3 видно.
4. Сборка + unit-тесты конвертера (escape, разбор атрибутов) проходят.

## Реализация (план)

| Компонент | Файл |
|-----------|------|
| XmlFragment → HTML | `Utils/XmlFragmentToHTML.swift` |
| Чтение в RecipeData | `Services/YjsSync/DocumentManager.swift` → `readDescription` v3 |
| UI | `Views/YDocRecipeDetailView.swift` — без изменений (уже `StepsSection`) |
| Тесты | `RecipeScalerNativeTests` |