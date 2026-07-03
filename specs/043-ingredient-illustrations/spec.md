# Спецификация: иллюстрации ингредиентов на iOS (паритет веба)

**Ветка**: `043-ingredient-illustrations` (реализация на `master`, коммит `30552e7`)  
**Дата**: 2026-07-03  
**Статус**: **P1 Done** (2026-07-03) — экран v3-рецепта view/edit + picker + lazy-resolve. P2 (Discover/Shopping) — отдельный срез. `layout.md` / audit — waived (UI принят вручную).
**Зависимости**: `002-native-editing` (сетка ингредиентов), `003-recipe-image-offline-cache` (паттерны кэша — только как референс; ассеты bundled), веб-фича ingredient illustrations (фазы 1–2 уже в `recipe-scaler-web`)  
**Эталон (веб)**:

- Планы: `recipe-scaler-web/.cursor/plans/ingredient_illustration_ui_526b2ac9.plan.md`, `ingredient_icon_picker_7bf14510.plan.md`
- UI: `IngredientIllustrationThumb`, `IngredientIllustrationPicker`, `search-ingredient-catalog.ts`
- Данные: `illustrationId` в Yjs-ингредиенте, `shared/data/ingredient-catalog/`, `registry.json`
- Док: `recipe-scaler-web/llm/INGREDIENT-ILLUSTRATIONS.md`

**Нативная реализация (P1)**:

- Модель: `IngredientData` — `illustrationId`, `illustrationPickerCleared`
- Codec/writer: `RecipeYjsCodec`, `RecipeYjsWriter`, partial bindings в `DocumentManager` / `YjsSyncService`
- UI: `IngredientIllustrationThumb`, `IngredientIllustrationPickerSheet`, сетка в `YDocIngredientsSection`; lazy-resolve — `IngredientIllustrationLazyResolve`
- Контракт сетки: [contracts/ingredient-grid-thumb.md](./contracts/ingredient-grid-thumb.md) (40 pt thumb вместо номера)

---

## Контекст

На вебе у строк ингредиента опционально хранится **`illustrationId`** (slug из каталога ~339 `ready` записей). В UI вместо номера строки показывается **thumb 40×40** с белым «полароид»-фоном; при отсутствии id — иконка **Bowl**. В **edit mode** thumb — кнопка: Sheet с поиском по каталогу и сеткой превью; сброс привязки пишет в Yjs (в т.ч. флаг `illustrationPickerCleared`, чтобы lazy auto-match не перезаписывал выбор пользователя).

Сервер, LLM-импорт, backfill и матчер — **вне scope этой спеки** (уже на бэкенде/вебе). iOS **потребляет** синхронизированное поле и **не ломает** wire при чтении чужих ключей. Редактирование `illustrationId` на iOS должно **синхронизироваться** с вебом через тот же Y.Doc.

### Решения продукта (зафиксированы с владельцем)

| Решение | Выбор |
|---------|--------|
| Объём v1 нативной спеки | **Отображение + picker в edit** (веб фазы 1+2 для экрана рецепта) |
| Источник JPEG | **Bundled thumb** (веб-вариант **120×120** px, см. `INGREDIENT_ILLUSTRATION_WEB_PX`) + bundled `registry` / `llm-catalog` для подписей и поиска |
| Список покупок / Discover | **P2** внутри этой спеки (после рецепта), если не вынесено в отдельный срез |
| Платформа UI | **Только iPhone** (основной таргет приложения); отдельный iPad layout / popover **не делаем** |
| Каталог + поиск (код) | **`RecipeScalerCore`**: модели, загрузка JSON, whitelist id, NFKD + token search (unit-тесты без SwiftUI) |
| JPEG + SwiftUI | **`RecipeScalerNative`**: Asset Catalog / Resources, thumb + picker (Watch / Share не рендерят ингредиенты — Core не тянем ради них) |
| Версия bundled каталога | **`catalogVersion`** в генерируемом `ingredient-catalog.manifest.json` (см. § Архитектурные решения) |

---

## Цель

Пользователь iOS видит те же декоративные иконки ингредиентов, что на мобильном вебе: в **просмотре** и **редактировании** v3-рецепта, с возможностью **вручную выбрать или сбросить** иконку в edit mode. Данные остаются в Yjs; офлайн отображение работает за счёт bundled thumbs.

## Non-goals

- Генерация/админка каталога, LLM-промпты, серверный backfill, MCP/REST-only правки.
- PDF export на iOS.
- Picker в списке покупок (веб тоже без picker там).
- Автоматический пересчёт `illustrationId` при каждом изменении `name` на клиенте (ручной id сохраняется до «Сбросить»).
- Подгрузка 1024px master с CDN (выбран bundled thumb).
- Watch / Share Extension UI ингредиентов (если extension не рендерит рецепт — не трогаем).
- **iPad**: отдельные макеты, popover, split-view — вне scope; picker всегда **bottom sheet** как на iPhone.

---

## Пользовательские сценарии

### US-1 — Просмотр рецепта с иконками (Priority: P1)

**Как** пользователь, **я** открываю свой v3-рецепт, **чтобы** в списке ингредиентов вместо номера строки видеть узнаваемую картинку продукта (как на вебе).

**Независимая проверка**: рецепт с хотя бы одним `illustrationId` в Yjs → на симуляторе в view mode у строки thumb, у заголовка секции — пустой слот той же ширины.

**Приёмка**:

1. **Given** ингредиент с валидным `illustrationId`, **When** экран деталей в view mode, **Then** слева от имени thumb 40×40, `object-cover`, белый фон контейнера (light/dark).
2. **Given** ингредиент без id / невалидный slug / нет файла в bundle, **When** view mode, **Then** Bowl-плейсхолдер в том же слоте.
3. **Given** строка-заголовок (`isHeaderRow`), **When** любой режим, **Then** пустой слот фиксированной ширины (без номера и без thumb).
4. **Given** рецепт синхронизирован с веба после правки иконки, **When** pull/sync на iOS, **Then** thumb обновляется без перезапуска приложения.

---

### US-2 — Редактирование: выбор и сброс иконки (Priority: P1)

**Как** пользователь, **я** в edit mode нажимаю на thumb, **чтобы** привязать другой продукт из каталога или убрать привязку.

**Независимая проверка**: edit mode → tap thumb → поиск «мука» → выбор → Yjs обновлён → повторное открытие экрана показывает новый thumb; «Сбросить» → Bowl и отсутствие `illustrationId` (и установка `illustrationPickerCleared` по контракту веба).

**Приёмка**:

1. **Given** edit mode, обычная строка с количеством, **When** tap по thumb, **Then** открывается picker в **bottom sheet** (единый паттерн для всех поддерживаемых устройств).
2. **Given** picker открыт, **When** ввод запроса с токенами и NFKD-эквивалентами (например «Steak» / «стейк»), **Then** сетка фильтруется по AND-логике токенов (правила search UI).
3. **Given** picker, **When** выбор ячейки каталога, **Then** в Y.Map ингредиента записывается `illustrationId`; UI строки обновляется.
4. **Given** picker, **When** «Сбросить привязку», **Then** ключ `illustrationId` удаляется; выставляется `illustrationPickerCleared: true` (wire parity с вебом).
5. **Given** заголовок секции, **When** edit mode, **Then** thumb не кнопка, picker не открывается.
6. **Given** view mode, **When** tap thumb, **Then** ничего (не кнопка).

---

### US-3 — Синхронизация и совместимость Yjs (Priority: P1)

**Как** клиент в мультиплатформенной синхронизации, **я** читаю и пишу новые ключи, **не** ломая старые рецепты и v1 JSON fallback.

**Приёмка**:

1. **Given** Y.Map с неизвестным ключом на ингредиенте, **When** decode, **Then** приложение не падает; известные поля маппятся в `IngredientData`.
2. **Given** локальное обновление `illustrationId`, **When** sync, **Then** веб видит то же значение после merge.
3. **Given** v1 recipe с JSON `ingredients`, **When** parse, **Then** опциональный `illustrationId` в JSON подхватывается, если присутствует.

---

### US-4 — Публичный / Discover рецепт (Priority: P2)

**Как** пользователь Discover, **я** вижу иконки в read-only списке ингредиентов публичного рецепта.

**Приёмка**: `DiscoverRecipeView` / read-only секция использует тот же thumb-компонент, без picker.

---

### US-5 — Список покупок (Priority: P2)

**Как** пользователь вкладки Shopping, **я** вижу thumb у пункта, если в Yjs shopping item есть `illustrationId` (схема v2 на вебе).

**Приёмка**: при add-from-recipe id копируется в shopping item (если ещё не копируется — доработать writer); legacy items без поля — Bowl или lazy resolve **не обязателен** в P2 (достаточно Bowl).

---

## Требования

### Данные и Yjs

- **FR-ILL-001** — В `IngredientData` добавить опциональные `illustrationId: String?` и `illustrationPickerCleared: Bool` (default `false`).
- **FR-ILL-002** — `RecipeYjsCodec.parseIngredientMap` / `parseJSONIngredients` читают `illustrationId` (string) и `illustrationPickerCleared` (bool).
- **FR-ILL-003** — `RecipeYjsWriter.writeIngredient` пишет `illustrationId` при non-nil; при сбросе — удаляет ключ; при clear из picker — пишет `illustrationPickerCleared = true`, при новом выборе — снимает флаг (parity с веб `updateIngredientField`).
- **FR-ILL-004** — Валидация slug: если id не в bundled whitelist каталога — UI показывает Bowl, **не** пишет исправление автоматически при чтении (опционально debug-log).
- **FR-ILL-005** — Обновить `docs/ARCHITECTURE.md` (native): поле ингредиента, bundled assets, cross-platform wire.

### Ассеты и каталог

- **FR-ILL-010** — Sync из `recipe-scaler-web` добавляет:
  - WebP thumbs `{id}.webp` 120×120 (alpha) → **app target** (`RecipeScalerNative/Resources/...`);
  - `ingredient-catalog.json` + **`ingredient-catalog.manifest.json`** → **RecipeScalerCore** bundle resource (runtime + CI).
- **FR-ILL-011** — Скрипт `scripts/sync-ingredient-illustrations.sh` (или `.mjs`): копирует web thumbs, генерирует JSON/manifest из `registry.json` / `llm-catalog.json`; при несовпадении числа `ready` id и файлов на диске — **exit 1**; детали в `plan.md`.
- **FR-ILL-014** — **`RecipeScalerCore`**: `IngredientIllustrationCatalog` (load, `contains(id:)`, `label(id:locale:)`, `search(query:locale:)` с NFKD + token AND); без SwiftUI/UIKit.
- **FR-ILL-012** — Bowl SVG/vector в SwiftUI (stroke parity с веб `Bowl`, ~22 pt внутри 40 pt слота).
- **FR-ILL-013** — Константы размеров: display **40 pt** слот; bitmap **120 px** (@3x от 40).

### UI — компоненты

- **FR-ILL-020** — `IngredientIllustrationThumb` (SwiftUI): props `illustrationId`, `isInteractive`, `onTap`; белый rounded rect фон; Image из bundle; accessibility: decorative рядом с именем — скрыть от VoiceOver; кнопка в edit — `accessibilityLabel` из i18n.
- **FR-ILL-021** — Заменить `IngredientRowMarkerSlot` номером/thumb: для нумеруемых строк — thumb; для `+` новой строки — оставить «+»; для header — пустой слот **той же ширины**, что thumb (40 pt, не legacy marker width), обновить `ingredients-grid-ui.md` / `RecipeRowLayoutMetrics` при необходимости.
- **FR-ILL-022** — `IngredientIllustrationPicker`: search field, lazy grid, clear, done; поиск делегирует **`IngredientIllustrationCatalog.search`** из Core.
- **FR-ILL-023** — Проводка: `RecipeEditViewModel` / `DocumentManager.updateIngredient` для partial update `illustrationId` без затирания остальных полей.
- **FR-ILL-024** — `layout.md` + `layout-audit.json` для thumb и picker (human review до финальной вёрстки); `audit-ui-layout.sh`.

### i18n и a11y

- **FR-ILL-030** — Ключи в `Localizable.xcstrings` (ru + en, без fallback в коде), паритет с веб namespace `recipes.ingredient-icon.*`:
  - `choose`, `picker-title` ({{name}}), `picker-search-placeholder`, `picker-clear`, `placeholder-alt`, `autodetected` (view-only tooltip при необходимости).
- **FR-ILL-031** — `AccessibilityIdentifiers`: `ingredient_icon`, `ingredient_illustration_picker`, `ingredient_picker_search`, `ingredient_picker_clear` (kebab в UI tests при необходимости).

### Тесты

- **FR-ILL-040** — Unit: codec round-trip `illustrationId` + `illustrationPickerCleared`; **`RecipeScalerCoreTests`** (или native tests against Core): catalog search (NFKD, токены), manifest ↔ thumb files count.
- **FR-ILL-041** — Unit/Snapshot: thumb placeholder vs image (stub id).
- **FR-ILL-042** — Обновить `LocalizationConsistencyTests` для новых ключей.

---

## Граничные случаи

- Старый iOS без поля в модели, новый Yjs с `illustrationId` → после обновления app thumb появляется (только forward decode).
- Пользователь очистил иконку на вебе (`illustrationPickerCleared`) → iOS не должен «догадываться» и подставлять matcher локально (matcher на iOS **не** в scope).
- Очень длинное имя ингредиента + thumb — сетка `002` не ломается: thumb `shrink-0`, ширина слота фиксирована.
- Рецепт v1/v2 read-only policy проекта: если editing недоступен — только US-1 view.
- Размер IPA: ~339 JPEG 120px — оценить в `plan.md`; при превышении бюджета — эскалация (не CDN в этой спеки без смены решения).

---

## Критерии успеха

- **SC-001** — На рецепте с 10+ размеченными ингредиентами список скроллится без jank; thumbs из bundle, без сетевых запросов.
- **SC-002** — Выбор иконки в edit на iOS виден на вебе после sync ≤ 1 обычного sync цикла.
- **SC-003** — `catalogVersion` в manifest совпадает с закоммиченным каталогом; 100% `ready` id имеют JPEG в app bundle (проверка sync-скрипта / unit на manifest).
- **SC-004** — Пользователь с VoiceOver слышит осмысленный label на кнопке thumb в edit; декоративный thumb в view не дублирует имя ингредиента.

---

## Допущения

- Веб уже выкатывает `illustrationId` в production Yjs; доля размеченных рецептов растёт (backfill/LLM) независимо от iOS.
- Thumb 120px из `ingredients/web/` визуально достаточен для 40 pt @3x.
- Для picker допустимо показать все ~339 ячеек с прокруткой при пустом поиске (как на вебе).
- Первая реализация shopping/Discover может идти вторым PR после merge ядра рецепта (P1 / P2 split).

---

## Связанные артефакты (создать по pipeline)

| Артефакт | Назначение |
|----------|------------|
| `specs/043-ingredient-illustrations/plan.md` | техплан, sync script, DI, порядок задач |
| `specs/043-ingredient-illustrations/tasks.md` | чеклист реализации |
| `specs/043-ingredient-illustrations/layout.md` | thumb + picker (ревью человеком) |
| `specs/043-ingredient-illustrations/contracts/yjs-ingredient-illustration.md` | wire keys |
| `specs/043-ingredient-illustrations/contracts/ingredient-grid-thumb.md` | обновление контракта сетки 002 |

---

## Архитектурные решения (зафиксировано)

### iPad

Не проектируем и не верифицируем. Picker — тот же **`.sheet` + detent bottom**, что и на iPhone; в `layout.md` только iPhone canvas.

### RecipeScalerCore vs app target

| Слой | Содержимое |
|------|------------|
| **RecipeScalerCore** | `IngredientIllustrationCatalog`, NFKD/token search, decode `ingredient-catalog.json`; опционально общий `IngredientIllustrationLayoutMetrics` (40 pt slot) если понадобится Watch позже |
| **RecipeScalerNative** | UIImage/Asset lookup по slug, `IngredientIllustrationThumb`, `IngredientIllustrationPicker`, Yjs codec/writer, интеграция в `YDocIngredientsSection` |

**Почему Core:** поиск и whitelist — чистая логика, тестируется без симулятора; codec может вызывать `contains(id:)` при валидации. **Почему не тащить JPEG в Core:** бандл картинок тяжёлый и нужен только main app; Watch/Share в этой фиче не потребители.

### `catalogVersion` (manifest)

Скрипт sync пишет **`RecipeScalerCore/Resources/ingredient-catalog.manifest.json`** (путь уточнить в `plan.md`):

```json
{
  "catalogVersion": "<sha256 первых 16 hex от canonical JSON ingredient-catalog.json>",
  "readyEntryCount": 339,
  "thumbPixelSize": 120,
  "source": "recipe-scaler-web/public/assets/illustrations/ingredients/web"
}
```

- **`catalogVersion`** меняется при любом изменении каталога (добавление id, aliases, labels) — разработчик перегоняет sync и коммитит JSON + manifest + JPEG в одном changeset.
- **CI / тест:** `readyEntryCount` == число `.webp` в app resources; unit-тест загружает manifest и сверяет с `IngredientIllustrationCatalog.entryCount`.
- Runtime **не** качает каталог с сети; версия только для ревью диффов и guard в тестах (не для OTA обновления каталога без релиза app).