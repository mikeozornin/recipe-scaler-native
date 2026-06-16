# Спецификация: импорт из Paprika и Crouton

**Ветка**: `027-paprika-crouton-import`  
**Дата**: 2026-06-15  
**Статус**: 🟢 Реализовано (аудит 2026-06-15)  
**Зависимости**: `010-recipe-import` ✅ (вкладка Import, навигация после успеха), `008-collection-mutations` ✅ (создание рецепта в коллекции), `016-recipe-image-upload` ✅ (фото рецепта), `026-recipe-collections` ✅ (маппинг категорий в папки через `resolveOrCreateFolderId`)  
**Эталон**: экспорт Paprika Recipe Manager (`.paprikarecipes` / `.paprikarecipe`), экспорт Crouton Recipe Manager (ZIP с `.crumb`); паритет поведения с batch-import на вебе (создание v3, sync на второй клиент)

## Audit table (2026-06-15)

| Area | Status | Notes |
|------|--------|-------|
| Foundational parsers + XmlWriter | ✅ | Paprika, Crouton, DescriptionXmlFragmentWriter |
| Format detector + ZIP UTF-8 fallback | ✅ | `decodeEntryPath` covers Crouton encoding bug |
| US1 Paprika archive batch | ✅ | ThirdPartyRecipeImportService wired into ImportRecipeSheet |
| US2 Single `.paprikarecipe` | ✅ | gzip magic detection |
| US3 Crouton ZIP | ✅ | `*.crumb` enumeration + `isSection` → heading |
| US4 Single `.crumb` | ✅ | Plain JSON detection |
| US5 Progress + cancel | ✅ | `Task.isCancelled`, progress callback |
| US6 Photo decode + upload | ✅ | base64 photo_data + images[0], offline skip + summary |
| US7 Metadata fields | ✅ | source/source_url, prep/cook, duration/cookingDuration, rawDifficulty |
| US8 Categories → folders | ✅ | `resolveOrCreateFolderId` + `applyCategoryLabelsToRecipe` (depends on 026) |
| US9 Unsupported / empty errors | ✅ | Localized, no collection mutation |
| US10 Offline + sync | ✅ | `deliverPendingLocalUpdate` per recipe |
| Unit tests (parsers, detector, XmlWriter) | ✅ | 18 green |
| Integration tests (DocumentManager) | 🟡 | `XCTSkip` — test host stalls on Yjs sync; CI host needed |
| Manual quickstart scenarios | 🟡 | Pending device smoke (T034/T038/T048/T051/T068/T069) |

## Контекст

Пользователи Paprika и Crouton накапливают сотни рецептов в закрытых форматах. Оба приложения умеют **экспортировать** данные в машинно-читаемые архивы; официальная документация есть у Paprika, у Crouton — только reverse-engineering сообществом (Mealie, Mela, gists).

Текущий импорт (spec **010**) рассчитан на **неструктурированный** контент (URL, текст, фото) и парсит его **на сервере** через LLM/OCR. Форматы Paprika/Crouton уже содержат поля `name`, `ingredients`, шаги, порции, фото — повторный LLM-парсинг избыточен, дорог и может исказить количества (нарушение FR-IMP-004 / PRD).

**Отличие от spec 020** (export/import аккаунта Recipe Scaler): там свой формат v1.0–v1.4 с `metadata.version`. Paprika/Crouton — **сторонние** форматы; общий только UX «выбрать файл → рецепты в коллекции».

### Форматы источников (исследование)

| Источник | Файл | Внутри | Кодировка |
|----------|------|--------|-----------|
| Paprika | `*.paprikarecipes` | ZIP → `*.paprikarecipe` | gzip + JSON на файл |
| Paprika | один `*.paprikarecipe` | — | gzip + JSON |
| Crouton | ZIP (имя произвольное) | `*.crumb` | UTF-8 JSON |
| Crouton | один `*.crumb` | — | UTF-8 JSON |

**Paprika — ключевые поля JSON** (стабильны с ~2012): `name`, `ingredients` (строка, `\n`), `directions` (строка, `\n`), `servings`, `prep_time`, `cook_time`, `categories[]`, `photo_data` (base64 JPEG), `source`, `source_url`, `rating`, `uid`, опционально `notes`, `nutritional_info`, `difficulty`.

**Crouton — ключевые поля JSON** (community schema): `name`, `uuid`, `serves` (число), `ingredients[]` (`quantity.amount`, `quantity.quantityType`, `ingredient.name`, `order`), `steps[]` (`step`, `order`, `isSection`), `images[]` (base64), `tags[]`, `rating`, `duration` / `cookingDuration`, `rawDifficulty`, `folderIDs[]`.

## Цель

Пользователь Recipe Scaler может **перенести библиотеку** из Paprika или Crouton одним действием «выбрать файл экспорта» на вкладке Import (и позже — Share Extension из spec **025**), без копирования текста и без потери названий, ингредиентов, шагов и фото.

Импорт **детерминированный** (без LLM): распознанные поля → v3 Y.Doc по [docs/YJS-SCHEMA.md](../../docs/YJS-SCHEMA.md). Работает **офлайн** для текстовых полей; загрузка изображений — при наличии сети (016).

## Пользовательские сценарии

### US1 — Импорт архива Paprika (P1)

**Когда** пользователь на вкладке Import выбирает файл `*.paprikarecipes` (или Share / Files отдаёт такой файл), **тогда** приложение распаковывает ZIP, читает каждый `.paprikarecipe`, создаёт v3-рецепты в коллекции и показывает итог: «Импортировано N из M».

**Acceptance**:

1. **Given** валидный архив с ≥3 рецептами, **When** импорт завершён, **Then** все три видны в списке с корректными названиями.
2. **Given** один рецепт в архиве, **When** импорт успешен, **Then** sheet закрывается и открывается экран этого рецепта (как US4 в 010).
3. **Given** архив с битым gzip в одном файле, **When** импорт, **Then** остальные рецепты импортированы, битый — в отчёте ошибок.

### US2 — Импорт одного рецепта Paprika (P1)

**Когда** выбран один файл `*.paprikarecipe`, **тогда** тот же pipeline, что US1, но без ZIP; результат — один рецепт + переход на detail.

### US3 — Импорт архива Crouton (P1)

**Когда** пользователь выбирает ZIP с файлами `*.crumb`, **тогда** каждый `.crumb` → v3-рецепт; structured ingredients и steps маппятся без LLM.

**Acceptance**:

1. **Given** Crouton-рецепт с `serves: 4` и тремя ингредиентами, **When** импорт, **Then** `servings == 4`, три строки ингредиентов в Y.Array.
2. **Given** шаг с `isSection: true`, **When** импорт, **Then** в описании — заголовок секции (не нумерованный пункт списка).

### US4 — Импорт одного `.crumb` (P2)

**Когда** выбран один `.crumb`, **тогда** импорт одного рецепта.

### US5 — Прогресс batch-импорта (P1)

**Когда** в архиве >5 рецептов, **тогда** показывается прогресс (текущий / всего), кнопка «Отмена» прерывает **дальнейшие** файлы (уже созданные рецепты остаются).

### US6 — Фото рецепта (P2)

**Когда** в источнике есть `photo_data` (Paprika) или `images[]` (Crouton), **then** первое фото загружается через pipeline 016 и привязывается к рецепту; при офлайне рецепт создаётся без фото, показывается ненавязчивое сообщение (ключ i18n, без fallback-строк).

### US7 — Метаданные источника (P2)

**Когда** есть `source_url` / `source`, **then** заполняются `originalRecipeLink` / `originalRecipe` в Y.Map.

**Когда** есть `prep_time` / `cook_time` (Paprika) или `duration` (Crouton), **then** они попадают в начало описания (plain block перед `<ol>` шагов), без выдумывания значений.

### US8 — Категории и теги → коллекции (P3)

**Когда** spec **026** реализован и в экспорте есть `categories[]` (Paprika) или `tags[]` (Crouton), **then** для каждой уникальной метки создаётся коллекция (если ещё нет) и рецепт получает соответствующий `folderIds`. До 026 — категории **не импортируются** (не теряем рецепт из-за отсутствия папок).

### US9 — Ошибки и неподдерживаемый файл (P1)

**Когда** файл не Paprika/Crouton (например `.txt`, export Recipe Scaler v1.3), **then** понятная локализованная ошибка «неподдерживаемый формат»; **не** смешивать с LLM-import pipeline 010 в одном submit без явного выбора режима.

### US10 — Синхронизация (P1)

**Когда** импорт завершён онлайн, **then** рецепты появляются на веб-клиенте после обычного sync; офлайн — в локальной коллекции и очереди sync.

## Функциональные требования

### FR-027-001 — Точка входа UI

- Новый режим или секция на `ImportRecipeSheet`: «Файл Paprika / Crouton» (i18n).
- `fileImporter` / document picker: UTType для `paprikarecipes`, `paprikarecipe`, `crumb`, generic `zip` + определение по содержимому.
- Тот же entry point допустим в Share Extension (025) — общий модуль парсинга в `RecipeScalerCore`.

### FR-027-002 — Детекция формата

Порядок:

1. Расширение / declared type.
2. Magic bytes: ZIP → перечислить entries; если все `*.paprikarecipe` → Paprika batch; если все `*.crumb` → Crouton batch; смешанный ZIP → ошибка.
3. Одиночный файл: попытка gzip-decompress + JSON (Paprika); иначе UTF-8 JSON с полями Crouton (`uuid` + `ingredients[]`).

### FR-027-003 — Маппинг в v3 (Y.Doc)

| Поле RS v3 | Paprika | Crouton |
|------------|---------|---------|
| `name` | `name` | `name` |
| `servings` | parse `servings` → int ≥1, default 1 | `serves` |
| `ingredients[]` | split `ingredients` по `\n`, trim пустые | map `ingredients[]` |
| `description` (XmlFragment) | `directions` → `<ol><li>…</li></ol>`; без префиксов «Шаг N» | `steps` where `!isSection` → `<ol>`; sections → `<h3>` |
| `originalRecipeLink` | `source_url` | — |
| `originalRecipe` | `source` | — |
| `version` | `"v3"` | `"v3"` |
| `hasSteps` | true если есть directions/steps | true если есть steps |

**Ингредиенты (FR-IMP-004 parity)**:

- Не вызывать LLM; не **выдумывать** количества.
- Paprika: каждая непустая строка → один Y.Map; best-effort split «количество + имя»; при сомнении — вся строка в `name`, `amount` пустой.
- Crouton: `amount` = человекочитаемая строка из `quantity.amount` + `quantityType` (например `225 g`); `name` = `ingredient.name`; без конвертации единиц в другую систему.

**Описание — notes**:

- Paprika `notes` → абзац `<p>` перед шагами, если не дублирует directions.

### FR-027-004 — Создание рецептов

- Использовать `DocumentManager.createRecipe` + последующие мутации ingredients/description (008/002 patterns).
- Batch: новый `recipeId` на файл; порядок в коллекции — порядок в архиве.
- Лимит v1: **500** рецептов за один импорт; при превышении — ошибка до начала с указанием лимита.

### FR-027-005 — Изображения

- Декод base64 (`photo_data`, `images[0]`); Paprika: нормализовать escaped `/` (`\/` → `/`).
- Upload через API 016; при ошибке одного фото — рецепт сохранён, фото пропущено, учёт в итоговом отчёте.

### FR-027-006 — i18n

Все строки UI и ошибок — ключи в `Localizable.xcstrings` (`import.paprika-*`, `import.crouton-*`); логи — English.

### FR-027-007 — Безопасность и приватность

- Парсинг только локально; сырой JSON экспорта **не** отправлять на сервер (кроме бинаря фото через image API).
- Не логировать base64 целиком; не сохранять временные файлы экспорта после завершения.

### FR-027-008 — Паритет веб (follow-up)

Нативная реализация — **первая** (offline-first). Веб получает те же парсеры в `recipe-scaler-web` (shared TS или порт с Swift) в отдельной задаче; контракт маппинга — [contracts/third-party-recipe-formats.md](contracts/third-party-recipe-formats.md).

## Вне scope

- HTML-экспорт Paprika (hrecipe) — только бинарный Paprika Recipe Format.
- Paprika grocery lists, meal plans, bookmarks.
- Crouton `folderIDs` без имён папок в экспорте (до появления маппинга в community schema).
- `nutritional_info` / макросы — v2 фича.
- Импорт из других приложений (Mela, Pestle, Recipe Keeper) — отдельные спеки.
- Серверный endpoint для Paprika/Crouton.

## Граничные случаи

- Пустой ZIP или архив без распознанных рецептов → ошибка, коллекция не меняется.
- Дубликат `name` в одном batch → всё равно создавать отдельные рецепты (новые UUID в нижнем регистре).
- Рецепт без названия → локализованное «Без названия» + имя файла как hint в логе.
- Очень большой JSON с фото (>25 MB на image policy 016) → пропуск фото с сообщением.
- Unicode `\uXXXX` в Crouton — стандартный JSON decode.
- Импорт во время активного sync — обычная очередь offline; без special case.
- Двойной submit — кнопка disabled на время processing.

## Критерии успеха

- **SC-001**: Архив Paprika (≥10 рецептов с фото) → все названия и ≥90% ингредиентов совпадают с Paprika при ручной выборочной проверке; время ≤2 мин на 50 рецептов на актуальном iPhone.
- **SC-002**: Архив Crouton (≥5 рецептов) → порции, ингредиенты и шаги читаемы в native detail без «Шаг 1» в тексте пунктов.
- **SC-003**: Один рецепт → автопереход на detail; batch → dismiss + toast/summary с count.
- **SC-004**: Офлайн batch без фото → рецепты в списке; после reconnect — sync на веб без дубликатов.
- **SC-005**: Неподдерживаемый файл → ошибка ≤3 с, без частичного мусора в коллекции.

## Допущения

- Пользователь получает файл экспорта через Files / AirDrop / email attachment; инструкция «Export from Paprika/Crouton» — в quickstart, не in-app tutorial v1.
- Форматы community-stable; breaking change Paprika/Crouton обрабатывается forward-compatible парсером (unknown keys ignored).
- Рейтинг (`rating`) не переносится — в RS нет поля; не блокирует импорт.
- Crouton `quantityType` enum ограниченный; неизвестные значения сериализуются as-is в `amount`.

## Артефакты

| Файл | Назначение |
|------|------------|
| [contracts/third-party-recipe-formats.md](contracts/third-party-recipe-formats.md) | Поля источников + таблица маппинга v3 |
| [research.md](research.md) | Ссылки на Mealie/Mela/pyprika, примеры JSON, fixture hashes |
| [quickstart.md](quickstart.md) | Как получить тестовый экспорт, прогон на симуляторе |
| `checklists/requirements.md` | Quality gate spec |
