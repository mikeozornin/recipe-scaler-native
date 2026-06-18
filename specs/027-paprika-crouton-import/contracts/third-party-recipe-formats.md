# Контракт: сторонние форматы рецептов → Recipe Scaler v3

**Feature**: `027-paprika-crouton-import`  
**Дата**: 2026-06-15  
**Статус**: Draft

Документ фиксирует **семантику маппинга** для детерминированного импорта. Целевая схема — [docs/YJS-SCHEMA.md](../../../docs/YJS-SCHEMA.md) (v3).

## 1. Paprika Recipe Format

### 1.1 Контейнер

| Уровень | Формат | Действие |
|---------|--------|----------|
| `.paprikarecipes` | ZIP archive | `ZipArchive` / `Archive` API |
| `.paprikarecipe` | gzip(body) → UTF-8 JSON | `Compression` framework или zlib |

Игнорировать entries без расширения `.paprikarecipe` (metadata, `__MACOSX`).

### 1.2 JSON — обязательные для импорта

| Ключ | Тип | → RS v3 |
|------|-----|---------|
| `name` | string | `recipe.name` |
| `ingredients` | string (`\n`) | `recipe.ingredients[]` |
| `directions` | string (`\n`) | `description` XmlFragment |

### 1.3 JSON — опциональные

| Ключ | Тип | → RS v3 | Примечание |
|------|-----|---------|------------|
| `servings` | string | `recipe.servings` | `"4"`, `"4-6"` → первое число или 1 |
| `prep_time` | string | description `.prepTime` signal | localized «Prep: …» by Native layer |
| `cook_time` | string | description `.cookTime` signal | localized «Cook: …» by Native layer |
| `notes` | string | description `<p>` | до шагов |
| `categories` | string[] | `folderIds` (P3, spec 026) | до 026 — skip |
| `photo_data` | string (base64) | `imageUrl` via upload | JPEG; unescape `\/` |
| `source` | string | `originalRecipe` | |
| `source_url` | string | `originalRecipeLink` | |
| `uid` | string | — | не сохранять (новый RS id) |
| `rating` | number | — | skip |
| `nutritional_info` | object/string | — | out of scope v1 |

### 1.4 Ingredients split (Paprika)

Вход: `"200 g муки\n3 яйца\n соль "`  

Алгоритм v1 (best-effort, без LLM):

1. Split by `\n`, trim, drop empty.
2. Для каждой строки `line`:
   - Regex prefix: `^([\d.,/\s]+(?:g|kg|ml|l|oz|lb|cup|cups|tbsp|tsp|шт\.?)?)\s+(.+)$` (case-insensitive) → `amount`, `name`.
   - Иначе: `name = line`, `amount = ""`.
3. Для строки с количеством: `ThirdPartyIngredientAmountSplitter` разделяет combined amount (`"200 g"`) → `amount` = `"200"`, `unit` = `"g"`.
4. Y.Map: `id` (UUID, lowercase), `name` (если `unit` непустой — `"{name}, {unit}"`, как server import), `amount` (число), `originalAmount` = `amount`, `unit`, `order` = 1-based index.

### 1.5 Directions → description

1. Split `directions` by `\n`, trim, drop empty.
2. Strip leading `\d+[\.\)]\s*` from each line (Paprika часто нумерует).
3. Output HTML:

```html
<!-- optional notes / times -->
<ol>
  <li>…</li>
</ol>
```

4. Insert into v3 `Y.XmlFragment('description')` via existing description write path (019).

---

## 2. Crouton `.crumb`

### 2.1 Контейнер

| Уровень | Формат |
|---------|--------|
| Export ZIP | один или более `*.crumb` |
| Single `.crumb` | plain JSON, UTF-8 |

### 2.2 JSON — обязательные

| Ключ | Тип | → RS v3 |
|------|-----|---------|
| `name` | string | `recipe.name` |
| `ingredients` | array | `recipe.ingredients[]` |
| `steps` | array | `description` |

Детекция Crouton: presence of `ingredients[].ingredient.name` or root `uuid` string.

### 2.3 Ingredients (Crouton)

```json
{
  "quantity": { "amount": 225, "quantityType": "GRAMS" },
  "ingredient": { "name": "Огурец", "uuid": "…" },
  "order": 0
}
```

Маппинг:

| Crouton | RS ingredient map |
|---------|-------------------|
| `ingredient.name` | `name` (если `unit` непустой — `"{name}, {unit}"`) |
| `quantity.amount` | `amount` (numeric string) |
| `quantity.quantityType` | `unit` (suffix, см. таблицу ниже) |
| `order` | `order` (1-based) |
| — | `id` = new UUID (lowercase) |
| `amount` | `originalAmount` = same as `amount` |

**quantityType → unit** (v1, без конвертации; `quantityType` не сохраняется отдельно):

| quantityType | `unit` |
|--------------|--------|
| `GRAMS` | `g` |
| `KILOGRAMS` | `kg` |
| `MILLILITERS` | `ml` |
| `LITERS` | `l` |
| `OUNCES` | `oz` |
| `POUNDS` | `lb` |
| `CUPS` | `cup` |
| `TABLESPOONS` | `tbsp` |
| `TEASPOONS` | `tsp` |
| `PIECES` / unknown | `""` |

Example: `{ amount: 225, quantityType: "GRAMS" }` → `amount: "225"`, `unit: "g"`.

### 2.4 Steps → description

For each `steps[]` sorted by `order`:

| Condition | HTML |
|-----------|------|
| `isSection == true` | `<h3>{step}</h3>` |
| else | `<li>{step}</li>` inside single `<ol>` |

Non-step sections break `<ol>`: close list before `<h3>`, open new `<ol>` after if needed.

### 2.5 Опциональные поля

| Ключ | → RS v3 |
|------|---------|
| `serves` | `servings` |
| `images[0]` | image upload |
| `tags[]` | `folderIds` (P3) |
| `duration`, `cookingDuration` | description `.durationMinutes` signal (Int minutes) → localized «N min» by Native layer; free-form strings pass through verbatim as `.paragraph` |
| `rawDifficulty` | description `.difficulty` signal (verbatim pass-through as `.paragraph`; no deterministic localization) |
| `folderIDs` | skip v1 (IDs without names in export) |
| `rating` | skip |

---

## 3. Общие правила записи

1. Всегда `version: "v3"`, `hasSteps: true` если description non-empty.
2. `createdAt` / `updatedAt` — ISO8601 UTC at import time (не сохранять source timestamps v1).
3. Collection entry — через тот же path, что `createRecipe` (008).
4. Partial batch failure: continue; return `{ imported: [ids], failed: [{ file, reason }] }`.
5. Max batch size: **500** recipes per operation.

### 3.1 Localization of synthesized metadata blocks (review #30)

Core parsers (`PaprikaRecipeParser`, `CroutonRecipeParser`) emit **structural
metadata signals** for `prep_time` / `cook_time` / `duration` / `rawDifficulty`
instead of pre-baking English text. `DescriptionBlock` carries these as
non-textual cases:

- `.prepTime(String)` — Paprika `prep_time` value
- `.cookTime(String)` — Paprika `cook_time` value
- `.durationMinutes(Int)` — Crouton numeric `duration` / `cookingDuration`
- `.difficulty(String)` — Crouton `rawDifficulty`

The Native layer (`RecipeScalerNative/Services/DescriptionBlockLocalizer.swift`)
resolves these into localized `.paragraph(String)` blocks using
`Bundle.currentLocalizedString` + `AppLanguagePreference.current.locale` **before**
the draft reaches `DescriptionXmlFragmentWriter.apply`. The Y.Doc schema is not
changed: prep/cook/duration remain stored as paragraphs inside the
`Y.XmlFragment('description')`.

Localizable keys:
- `recipe.import.metadata.prep-time %@`
- `recipe.import.metadata.cook-time %@`
- `recipe.import.metadata.duration-minutes %d`

`difficulty` is free-form text authored by the source recipe's user (e.g. "Easy",
"Лёгкий"); no deterministic localization applies, and it is emitted verbatim.

## 4. Test fixtures (research)

Минимальный набор для CI (добавить в `research.md` / test bundle):

- `fixtures/paprika/single-recipe.paprikarecipe` — gzip JSON, no photo
- `fixtures/paprika/three-recipes.paprikarecipes` — ZIP
- `fixtures/crouton/single.crumb` — JSON with 2 ingredients, 2 steps
- `fixtures/crouton/batch.zip` — 3× `.crumb`

Каждый fixture должен иметь ожидаемый `expected-name`, `expected-ingredient-count`, `expected-step-count` в sidecar JSON для unit tests.
