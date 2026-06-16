# Research: импорт Paprika / Crouton

**Feature**: `027-paprika-crouton-import`  
**Дата**: 2026-06-15

## R1 — Где парсить: клиент vs сервер

**Decision**: Парсинг и маппинг **полностью на клиенте** (`RecipeScalerCore`), запись в Y.Doc через `DocumentManager`.

**Rationale**:
- Форматы уже структурированы; LLM (pipeline 010) рискует исказить количества (FR-IMP-004).
- Constitution III: batch-импорт должен работать **офлайн** для текста; только фото требуют REST (016).
- Сырой JSON экспорта не должен уходить на сервер (FR-027-007).

**Alternatives considered**:

| Вариант | Почему отклонён |
|---------|-----------------|
| POST structured JSON на новый server endpoint | Нарушает «no backend changes»; утечка пользовательских данных |
| Конвертация в plain text → `RecipeImportAPI.importText` | Потеря структуры, LLM-галлюцинации, медленно на 500 рецептах |
| Только веб | Против offline-first; spec ставит native first |

---

## R2 — ZIP и gzip на iOS

**Decision**:
- **gzip** (`.paprikarecipe`): helper `Gunzip.decompress(Data) -> Data` на базе `Compression` / `libcompression` (без новой зависимости).
- **ZIP** (`.paprikarecipes`, Crouton export): добавить **ZIPFoundation** (SPM, MIT) — в проекте пока нет ZIP-ридера; Foundation не даёт удобного API для перечисления entries.

**Rationale**: Mealie (`paprika.py`) использует `zipfile` + `GzipFile` — тот же двухуровневый pipeline. ZIPFoundation — de-facto стандарт для Swift.

**Alternatives considered**:
- Shell-out / `Process` — запрещено на iOS.
- Ручной minizip — лишняя поддержка.

---

## R3 — Запись v3 description (XmlFragment)

**Decision**: Новый **`DescriptionXmlFragmentWriter`** в `RecipeScalerCore` — запись Prosemirror-совместимых узлов через **yrs FFI** (`paragraph`, `heading`, `orderedList` → `listItem` → `paragraph` → text). Паттерн — `YrsDescriptionRoundtripTests.testYrsEncodeYjsDecodeMultiEdit`.

**Rationale**:
- Batch-импорт 500 рецептов не может поднимать WKWebView/Tiptap на каждый.
- `XmlFragmentToHTML` уже читает `orderedList` / `listItem`; roundtrip-тесты подтверждают совместимость с yjs 13.
- HTML string → applyUpdate через JS **не** используем (yrs re-encode ломает web parse — см. комментарий в `DocumentManager.applyDescriptionEditorUpdate`).

**Alternatives considered**:
| Вариант | Почему отклонён |
|---------|-----------------|
| Headless Tiptap в WKWebView | Медленно, хрупко, не offline-friendly |
| Plain `recipeMap.description` string | Только v1/v2; импорт всегда v3 |
| `AssistantMarkdownRenderer` → AttributedString | Нет записи в Y.Doc |

**Mapping steps → XmlFragment**:
- Paprika `directions` lines → один `orderedList` с `listItem` per line (strip `\d+.` prefix).
- Crouton `steps[]`: `isSection` → `heading` level 3; иначе `listItem` в текущем `orderedList` (close/open list around sections per contract).

---

## R4 — Промежуточная модель

**Decision**: `ThirdPartyRecipeDraft` (Sendable struct) — normalized DTO после парсера, до Y.Doc:

```swift
struct ThirdPartyRecipeDraft {
    var name: String
    var servings: Int
    var ingredients: [IngredientDraft]
    var descriptionBlocks: [DescriptionBlock]  // paragraph | heading | orderedListItem
    var originalRecipe: String?
    var originalRecipeLink: String?
    var imageData: Data?  // decoded JPEG/PNG bytes
    var sourceFileName: String  // for error reports
}
```

Парсеры Paprika/Crouton возвраща `[ThirdPartyRecipeDraft]` или `Result`.

**Rationale**: Один `ThirdPartyRecipeImporter` пишет в Y.Doc; тесты парсеров без yrs.

---

## R5 — Оркестрация и прогресс

**Decision**: `ThirdPartyRecipeImportService` (@MainActor) в `RecipeScalerNative`:

1. `detectFormat(url:) -> ThirdPartyFormat`
2. `import(url:progress:)` → `ThirdPartyImportResult`
3. Для каждого draft: `createRecipe` → batch `addIngredient` → `DescriptionXmlFragmentWriter.apply` → optional `RecipeImageUploadAPI.upload`
4. `progress: (Int, Int) -> Void` для UI; `Task.isCancelled` проверка между рецептами.

**Rationale**: `DocumentManager` уже `@MainActor`; импорт — UI-bound операция с progress.

**Batch debounce**: Не debounce каждый ingredient отдельно — одна write transaction per recipe где возможно (extend `DocumentManager` метод `applyImportedRecipe(draft:)`).

---

## R6 — Референсные реализации (community)

| Источник | URL | Что взять |
|----------|-----|-----------|
| Mealie Paprika migrator | [mealie/services/migrations/paprika.py](https://github.com/mealie-recipes/mealie/blob/mealie-next/mealie/services/migrations/paprika.py) | `paprika_recipes()` generator: ZIP extract → glob `*.paprikarecipe` → GzipFile → json.load; base64 `photo_data` |
| Mealie commit #2434 | [c25b58e](https://github.com/FelicixAwe/mealie/commit/c25b58e40464a0fe01e9ba73bb41f33796e0b132) | Aliases: `source_url`, `prep_time`/`cook_time`, categories → tags |
| Self-hosting guide | [recipe-import-guide](https://selfhosting.sh/foundations/recipe-import-guide/) | UX: `.paprikarecipes` direct import |
| Crouton | Community gists / Mela converter | `.crumb` = plain JSON; structured ingredients — **нет официальной схемы**, парсер tolerant к unknown keys |

**Fixture strategy**: Синтетические minimal JSON в repo (`RecipeScalerNativeTests/Fixtures/ThirdPartyImport/`) + один real export от maintainer (gitignored, documented in quickstart).

---

## R7 — UTType и fileImporter

**Decision**: Расширить `ImportRecipeSheet` режимом `file`:

- Declared types: `UTType(filenameExtension: "paprikarecipes")`, `"paprikarecipe"`, `"crumb"`, `UTType.zip`, `UTType.data` (fallback).
- После pick — `startAccessingSecurityScopedResource()`; copy to temp if needed; detect by content.

**Rationale**: iOS не знает Paprika UTType out of the box — custom extensions + zip fallback.

---

## R8 — Изображения

**Decision**: После `createRecipe`, если `imageData != nil` и online → `RecipeImageUploadPreprocessor` + `RecipeImageUploadAPI.upload` (016). Offline → skip + `import.third-party.photo-skipped-offline` в summary.

**Rationale**: FR-IMG-UP-001 — URL приходит через sync после upload; не писать `imageUrl` вручную в Y.Doc.

---

## R9 — Категории → коллекции (P3)

**Decision**: Отложить до **026** landed. В MVP парсеры **сохраняют** `categories`/`tags` в draft, importer **игнорирует** если `RecipeFolderService` недоступен.

**Rationale**: Spec US8 = P3; не блокирует MVP.

---

## R10 — Паритет веб UI

**Decision**: Native first; веб — отдельный follow-up: порт `ThirdPartyRecipeDraft` mappers на TypeScript в `recipe-scaler-web/src/services/importers/third-party/`.

**Rationale**: FR-027-008; constitution II соблюдён на уровне **Y.Doc shape**, не entry point parity.

---

## Resolved clarifications

Все технические unknowns из Technical Context закрыты; NEEDS CLARIFICATION не осталось.
