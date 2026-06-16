# Спецификация: Экспорт и импорт данных аккаунта (локально)

**Ветка**: `029-account-data-export-import`
**Дата**: 2026-06-16
**Статус**: 🟡 В работе
**Зависимости**: `013-account-settings` (Profile), `010-recipe-import` (import pipeline), `027-paprika-crouton-import` (ThirdPartyRecipeDraft — не реюз, но паттерн), `026-recipe-collections` (folders)
**Эталон**: веб `/account` page (Data Management), PRD § Export
**Перенесено из**: [020-account-telegram-export](../020-account-telegram-export/spec.md) US3/US4

## Контекст

Формат эталонный — Recipe Scaler JSON/ZIP v1.0–v1.4. Веб уже имеет полный набор парсеров, сериализаторов и JSON Schema (`src/services/exporters/v1.4-exporter.ts`, `src/services/importers/v1.4-importer.ts`, `src/schemas/export-schema-v1.4.json`). Нативный парсер — порт на Swift.

`ThirdPartyRecipeDraft` — lossy для нативного round-trip (нет `id`, `color`, `nutrition`, точных дат, `folderIds`). Вводим `NativeRecipeDraft`.

Архитектура: полностью локально, офлайн-first, через Y.Doc. Синк идёт через существующий Y.Doc pipeline после записи.

## Цель

Экспорт всех рецептов (с папками и изображениями) в нативный формат Recipe Scaler v1.4 JSON/ZIP и импорт v1.0–v1.4 обратно, с точками входа в Профиле (Data Management) и в существующем ImportRecipeSheet.

## Пользовательские сценарии

### US1 — Export всех данных (P2)

**Когда** пользователь нажимает «Экспортировать все рецепты» в разделе «Управление данными» (Profile), **тогда** приложение собирает все рецепти из Y.Doc, упаковывает в JSON/ZIP v1.4 (с изображениями) и предлагает Share Sheet.

**Детали**:
- Формат: v1.4 JSON (без изображений) или ZIP (с изображениями).
- Имя файла: `recipe-scaler-<ISO8601-timestamp>.json` или `.zip` (колоны/точки заменены на дефисы).
- ZIP layout: `recipes.json` + `images/<recipeId>/full.webp` + `images/<recipeId>/preview.webp`.
- Прогресс-бар для большого числа рецептов.
- Офлайн: работает полностью (реквизиты и описание — из локального Y.Doc, изображения — из кеша).
- Если рецептов нет: сообщение `account.data.export.nothing`.

### US2 — Import файла (P2)

**Когда** пользователь выбирает `.json`/`.zip` (v1.0–v1.4), **тогда** парсит, валидирует, создаёт рецепты/папки в Y.Doc через DocumentManager, загружает изображения если онлайн.

**Детали**:
- Точки входа: (a) Data Management → «Импортировать из файла», (b) ImportRecipeSheet → режим «Файл».
- Версии: v1.0–v1.4, backward compat (отсутствует `metadata.version` → v1.0).
- Лимиты: 500 рецептов, 25 MB/image (переиспользуем `ThirdPartyImportLimits`).
- Офлайн: рецепты импортируются, изображения skip'аются с предупреждением.
- Онлайн: после каждого `applyNativeRecipe` — `uploadImportedRecipeImage` (full, иначе preview), с `flushImportSyncBeforeImageUpload` и ретраями 404; не отдельной batch-фазой после всех рецептов.
- Прогресс: `N из M рецептов импортировано`.
- Результат: toast/сообщение с `importedCount`, `foldersImported`, `imagesUploaded`, warnings/errors.
- Folder ID remapping: old folder ID → new folder ID при импорте (как в вебе).

### US3 — Офлайн / безопасность (P2)

**Когда** пользователь офлайн, **тогда**:
- Экспорт работает (локальные данные).
- Импорт рецептов работает, изображения skip'аются с i18n предупреждением.
- Не логировать чувствительные данные.

## Требования

### FR-029-001 — NativeRecipeDraft (Core)

Новый тип `NativeRecipeDraft` в `RecipeScalerCore/Export/Native/`, зеркальный к `RecipeData + CollectionEntry + RecipeFolder`. Не реюзить `ThirdPartyRecipeDraft` (lossy).

### FR-029-002 — NativeRecipeExporter (Core)

Сериализация `RecipeData[] + RecipeFolder[] + folderIds mapping + imageBytes` → JSON Data или ZIP Data. ZIP через ZIPFoundation write path. Версия: всегда v1.4.

### FR-029-003 — NativeRecipeImporter (Core)

Парсинг JSON/ZIP URL → `NativeRecipeDraft[] + NativeFolderDraft[] + imageEntries`. Поддержка v1.0–v1.4. ZIP через ZIPFoundation read path.

### FR-029-004 — NativeFormatVersion + Detector + Validator (Core)

- `NativeFormatVersion` enum (v1_0–v1_4) + `normalizeVersion`.
- `NativeFormatDetector`: JSON vs ZIP, чтение `metadata.version`.
- `NativeFormatValidator`: per-version structural validation.

### FR-029-005 — YjsSyncService read pass-through

Добавить публичный `readRecipeData(recipeId:) async throws -> RecipeData?` на `YjsSyncService` (pass-through к `DocumentManager`).

### FR-029-006 — DocumentManager native import writer

Добавить `applyNativeRecipe(_ draft: NativeRecipeDraft) async throws -> String` — полная запись Y.Map с preserve ID (опционально), color, servings, nutrition, imageUrl, dates, originalRecipe/Link, затем `setRecipeFolders`.

**Описание (description)** парсится из HTML-строки в `RecipeDescriptionDocument` через `RecipeDescriptionParser` и пишется в Y.XmlFragment через `RecipeDescriptionXmlFragmentWriter` как дерево узлов `paragraph` / `heading[level]` / `orderedList` / `listItem` / `bulletList` с инлайн-элементами `bold` / `italic` / `link[href]` / `timer[data-duration,data-type,data-name,data-value]` / `ingredient[data-ingredient-id,data-ratio,data-original-amount]`. Паритет с веб-эталоном Tiptap/y-prosemirror (`specs/019-recipe-description-inline-edit/contracts/description-markup-parity.md`). round-trip покрывается тестами в `NativeFormatHtmlImportRoundtripTests` и Node-скриптом `scripts/test-yjs-description-roundtrip.mjs`.

### FR-029-007 — NativeExportImportService (Native)

Оркестрация: `exportAll(progress:) async throws -> URL` и `importFile(url:isOnline:progress:) async throws -> NativeImportResult`. `@MainActor`, инжектится с `YjsSyncService`.

### FR-029-008 — DataManagementView (UI)

Новый экран в Профиле (замена заглушки `account.data.coming-soon`). Секции: экспорт (кнопка + прогресс + ShareLink), импорт (кнопка + fileImporter + прогресс + результат).

### FR-029-009 — ImportRecipeSheet роутинг

Расширить fileSection: если файл — native Recipe Scaler (detect версии), роутить в `NativeExportImportService.importFile`. Иначе — как сейчас (Paprika/Crouton/text).

### FR-029-010 — i18n

Все строки в `Localizable.xcstrings` (ru/en). Ключи `account.data.export.*`, `account.data.import.*`. Без fallback-строк.

### FR-029-011 — Тесты

Unit-тесты: exporter round-trip, importer per-version fixtures, version normalization, validator positive/negative.

## Вне scope

- PDF cookbook
- Аккаунт-уровневый экспорт настроек/профиля (только рецепты + папки + изображения)
- Импорт Mealie/Tandoor/Nextcloud/Chowdown/Saffron
- Share Extension (spec 025 — отдельная задача)
- Deep-link на экран Data Management
- Бекенд-эндпоинт для export/import

## Критерии успеха

- **SC-001**: Export → валидный v1.4 JSON/ZIP файл, открываемый вебом (структурно идентичен `exportV1_4` из веба).
- **SC-002**: Import `.zip`/`.json` v1.0–v1.4 → рецепты появляются в коллекции, папки создаются, folderIds маппятся, изображения загружаются (онлайн).
- **SC-003**: Офлайн — экспорт работает, импорт рецептов работает, изображения skip'аются с i18n предупреждением.
- **SC-004**: Round-trip (export → import) — все поля сохраняются (name, description, ingredients, color, servings, nutrition, folders, images).

## Артефакты

- [plan.md](plan.md)
