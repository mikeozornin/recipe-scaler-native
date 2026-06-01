# Контракт: отображение списка рецептов (iOS ↔ мобильный web)

**Статус**: принято (реализовано 2026-06-02)  
**Связанные FR**: `001-yrs-native-read/spec.md` — FR-019, FR-020, FR-021  
**Эталон (web)**: `recipe-scaler-web/recipe-scaler/src/pages/recipe-list.tsx`, `shared/utils/recipe-title-emoji.ts`, `use-yjs-sync.ts` → `sortCollectionsByDisplayName`

## 1. Метрики строки (FR-019)

| Параметр | Значение | Web-класс / стиль |
|----------|----------|-------------------|
| Min height строки | 44 pt | `min-h-[44px]` |
| Padding vertical | 10 pt | `py-2.5` |
| Размер шрифта названия | 16 pt | `text-base`, `font-sans` на `h3` |
| Межстрочный интервал (2+ строки) | +8 pt line spacing | ~1.5 line-height для 16 pt |
| Выравнение маркер + текст | top | `items-start` |
| Превью изображения | 44×44 pt, cover, **с локального кэша** | inline style height/width 44px; загрузка — см. `003-recipe-image-offline-cache` |

## 2. Ведущее эмодзи (FR-020)

Поведение **идентично** `recipe-title-emoji.ts`:

- `getLeadingEmoji(name)` — одна emoji-последовательность в начале (после пробелов): обычные pictographic, ZWJ-цепочки, regional indicator (флаги), keycap (`1️⃣`)
- `getTitleWithoutLeadingEmoji(name)` — убрать ведущую последовательность и следующие пробелы
- Эмодзи не в начале `name` не трогается

**UI**:

- Если есть leading emoji → `Text(emoji)` 18 pt, колонка 12 pt, `padding.leading -4`, `padding.top 2`
- Иначе → `Circle` 12×12, цвет `color` или `oklch(0.65 0.25 270)`, `padding.top 6`
- Текст строки = display name; пустой → `recipe.list.no-title` / «Без названия»

## 3. Сортировка и pin-секции (FR-021)

### Алгоритм сортировки

```text
sort(entries):
  pinned first (isPinned true before false)
  then compareRecipeNamesIgnoringLeadingEmoji(a.name, b.name)
  then full name localeCompare (base)
  then id localeCompare (base)
```

Эквивалент веб:

```typescript
// use-yjs-sync.ts — sortCollectionsByDisplayName
```

### Структура UI

```text
[Section: «Закрепленные» + icon pin]  — только если есть pinned
  ... pinned rows (уже отсортированы) ...
[Section: «Рецепты»]                  — только если есть и pinned, и unpinned
  ... unpinned rows ...
```

Без inline pin в строке (на вебе pin — swipe, не иконка в title).

## 4. Реализация iOS

| Компонент | Файл |
|-----------|------|
| Emoji + compare + sort | `RecipeScalerNative/Utils/RecipeTitleEmoji.swift` |
| Список, секции, row UI | `RecipeScalerNative/Views/RecipeListView.swift` |
| Превью (offline-first) | `RecipeCachedImageView.swift`, `RecipeImageService.swift` — [003](../../003-recipe-image-offline-cache/spec.md) |
| `CollectionEntry.sorted` | `RecipeScalerNative/Models/YDoc/CollectionEntry.swift` |
| i18n секций | `recipe.list.section.pinned`, `recipe.list.section.unpinned`, `recipe.list.no-title` |

## 5. Слияние метаданных collection ↔ recipe (цвет, имя, превью)

**Эталон (web)**: `use-yjs-sync.ts` — список из `Y.Array('recipes')`; экран рецепта подставляет collection, если в recipe-доке поле пустое; при расхождении после sync с веба collection часто обновляется раньше recipe-дока.

| Поле | Правило iOS (`RecipeCollectionMerge`) |
|------|----------------------------------------|
| `name` | recipe, если непустое; иначе `entry.name` |
| `color` | recipe, если пустое; иначе `entry.color`, если `entry.updatedAt >= recipe.updatedAt` и нормализованные цвета различаются |
| `imageUrl` | recipe, если непустое; иначе `entry.imageUrl` |

**Когда применять**:
- `YjsSyncService.refreshCurrentRecipe` после `readRecipeData`
- `YjsSyncService.refreshCollectionEntries` → `syncActiveRecipeFromCollection` для `activeRecipeId`

**Ручная проверка**:
1. На вебе сменить цвет рецепта.
2. На iOS в списке — новый цвет (точка/акцент).
3. Открыть рецепт — accent на экране детали совпадает со списком.

**Крэш при сохранении цвета (iOS, 2026-06-02-010558.ips)**:
- Цепочка: `updateRecipeColor` → `updateCollectionEntry` → observer → `refreshCollectionEntries` → `RecipeListView.filteredEntries` → `RecipeTitleEmoji.sortCollectionEntries` → инициализация regex.
- Не падение в `ymap_insert(color)`; лечится безопасной компиляцией regex (`RecipeTitleEmoji.compileRegexes`, fallback-first).
- Unit: `testUpdateRecipeColorThenSortCollectionDoesNotCrash`.

## 6. Превью изображения (offline-first)

Полная спека: **`specs/003-recipe-image-offline-cache/`**.

Кратко:

- `imageUrl` в Y.Doc — индикатор и версия, не URL для `AsyncImage`.
- Байты: `GET /api/recipes/:id/image?preview=true&v=…` → `Caches/RecipeImages/{id}_preview.webp`.
- UI читает только с диска; prefetch после sync коллекции (до 3 параллельно).

## 7. Тесты

- Unit: `testRecipeTitleEmojiLeading`, `testRecipeTitleEmojiDisplayName`, `testRecipeTitleEmojiSortOrder` в `RecipeScalerNativeTests.swift`
- Unit: `testRecipeCollectionMergeUsesCollectionColorWhenNewer`, `testRecipeCollectionMergeUsesRecipeColorWhenRecipeNewer`, `testRecipeCollectionMergeUsesCollectionWhenRecipeColorEmpty` в `RecipeScalerNativeTests.swift`
- Unit (изображения): `testRecipeImageVersionToken` — см. `003-recipe-image-offline-cache/quickstart.md`
- Ручной: чеклист в `quickstart.md` § «Проверка паритета списка рецептов»; изображения — `003-recipe-image-offline-cache/quickstart.md`