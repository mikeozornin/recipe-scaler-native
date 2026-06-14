# Спецификация: импорт рецептов

**Ветка**: `010-recipe-import`  
**Дата**: 2026-06-02  
**Статус**: 🟢 Реализовано почти полностью (аудит 2026-06-03, подтверждено 2026-06-15)  
**Зависимости**: `008-collection-mutations` (новый рецепт в коллекции), `007` (Import tab)  
**Эталон**: `ImportRecipeSheet`, PRD § Import

## Аудит реализации (2026-06-15)

Вкладка Import и sheet в `AppShellView`; flow URL/текст/фото, multipart, batch URL, классификация, локализованные ошибки, offline «Try later», toast через `TransientStatusBanner`. i18n `import.*`.

| Требование | Статус |
|------------|--------|
| US1 импорт URL (1 или много, ≤25) | ✅ |
| US2 импорт текста | ✅ |
| US3 импорт фото (≤8, multipart multi-image) | ✅ |
| US4 навигация после успеха (1 → detail, 2+ → список) | ✅ |
| US5 локализованные ошибки | ✅ |
| US6 offline «Попробовать позже» | ✅ |
| US7 upload текстового файла (.txt / .md / .json / …) | ❌ нет `.fileImporter` — только paste в текстовое поле |
| Sheet UX: `.presentationDetents([.large])` | ✅ |
| Toast об успехе через `TransientStatusBanner` | ✅ |
| Share/Action Extension entry point | ✅ → [025-share-extension](../025-share-extension/spec.md) |
| Импорт файла export `.json/.zip` | ❌ → spec **020** |

## Прошлый аудит (2026-06-06)

US7 ошибочно помечен ✅ — исправлено в аудите 2026-06-15.

## Прошлый аудит (2026-06-03)

Реализовано: `ImportRecipeSheet` (URL/текст/фото), `RecipeImportAPI`, навигация на новый рецепт через `onImport`.

| Требование | Статус |
|------------|--------|
| US1 импорт URL | ✅ |
| US2 импорт текста | ✅ |
| US3 импорт фото (≤8, multipart) | ✅ |
| US4 навигация после успеха | ✅ |
| US5 ошибки | ✅ |
| Импорт файла export `.json/.zip` | ❌ не реализовано |

Импорт файла export связан с export/import аккаунта → закрывается в **020-account-telegram-export** (общий file pipeline). Строки sheet — на английском (см. 022).

## Контекст

Центральная вкладка Import на мобильном вебе открывает sheet с режимами:

- URL  
- Свободный текст  
- Фото (≤8, ≤25 MB, preprocessing на сервере)  
- Импорт файла export (.json / .zip v1.0–v1.3) — уточнить паритет с `docs/PRD.md` US6

Парсинг — **на сервере** (LLM/OCR); iOS не дублирует логику.

## Цель

Те же входы и пост-условия, что мобильный веб: после импорта — рецепт в коллекции и переход на `/recipe/:id`.

## Пользовательские сценарии

### US1 — Импорт по URL (P1)

**Когда** пользователь вводит URL, **тогда** `POST` parse/import endpoint (см. `llm/API.md`), прогресс, результат → сохранение в Y.Doc через сервер + sync на клиент.

### US2 — Импорт текста (P1)

**Когда** вставлен текст рецепта, **тогда** тот же pipeline; v3 steps как ordered-list HTML без «Шаг 1» (PRD).

### US3 — Импорт фото (P2)

**Когда** выбрано 1–8 фото из галереи/камеры, **тогда** multipart upload, лимиты PRD; JPEG preprocessing на сервере.

### US4 — Навигация после успеха (P1)

**Когда** один `recipeId`, **тогда** dismiss sheet + push detail с флагом «новый рецепт» (как `state: { isNewRecipe: true }` на вебе).

### US5 — Ошибки (P1)

Сетевые и validation ошибки — локализованные toast/alert; без частичного мусора в коллекции.

## Требования

### FR-IMP-001 — API (без изменения контракта)

Использовать существующие endpoints из `docs/PRD.md` §7:

- `POST /api/v2/recipes/:id/parse` (или актуальный flow создания id — сверить с веб `import-recipe-sheet`)
- `POST /api/recipes/import/image`

Точные пути — в `contracts/recipe-import-api.md` при implement.

### FR-IMP-002 — Создание документа

Сервер создаёт/обновляет recipe + collection entry; iOS принимает через `recipe_updated` / `collection_updated`, не пишет parse result вручную в CRDT (если только сервер не отдаёт yjs state — уточнить в research).

### FR-IMP-003 — UI

- Sheet из tab Import (007).
- Поля: URL, multiline text, photo picker.
- Индикатор загрузки; блокировка повторного submit.

### FR-IMP-004 — Имена ингредиентов

Паритет PRD: не выдумывать количества; сохранять имена из источника.

## Вне scope

- Импорт через Telegram (бот → уже на сервере)
- Редактирование результата до save (опционально v2)

## Критерии успеха

- **SC-001**: URL импорт iOS → тот же рецепт на вебе (name + ≥3 ingredients) ≤ 30 с.
- **SC-002**: Текст импорт — `version` v3 на вебе.
- **SC-003**: Отмена/ошибка не оставляет пустой entry в коллекции.

## Артефакты

- `contracts/recipe-import-api.md`
- `quickstart.md`