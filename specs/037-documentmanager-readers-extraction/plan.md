# Plan: DocumentManager readers extraction (#037)

План реализации scope A: один `RecipeYjsCodec` + схлопывание `RecipeReader.swift` + фикс `hasQuantity`.

## Шаги

### 1. Создать `RecipeScalerNative/Services/YjsSync/RecipeYjsCodec.swift`

`enum RecipeYjsCodec` со всеми static func (без actor state, чистые функции).

Переносятся из `DocumentManager.swift`:

| Метод | Откуда | Сигнатура |
|---|---|---|
| `parseCollectionEntry` | L1527 | `static func parseCollectionEntry(from map: YrsMap, txn: OpaquePointer) -> CollectionEntry` |
| `parseRecipeData` | L1546 | `static func parseRecipeData(from:txn:recipeId:) -> RecipeData` |
| `readRecipeName` | L1573 | `static func readRecipeName(from:txn:) -> String` |
| `readDescription` | L1585 | `static func readDescription(from:txn:version:) -> String?` |
| `readSearchIngredients` | L1608 | `static func readSearchIngredients(from:txn:version:) -> SearchIngredientProjection` |
| `searchIngredientsFromJSON` | L1641 | `static func searchIngredientsFromJSON(_ json: String) -> SearchIngredientProjection` |
| `readIngredients` | L1674 | `static func readIngredients(from:txn:version:preferArray:) -> [IngredientData]` (новый параметр, default false) |
| `readNutrition` | L1696 | `static func readNutrition(from:txn:version:) -> NutritionData?` |
| `parseIngredientMap` | L1743 (static) | `static func parseIngredientMap(_:txn:fallbackOrder:) -> IngredientData` |
| `parseJSONIngredients` | L1863 | `static func parseJSONIngredients(_ json: String) -> [IngredientData]` |
| `parseJSONNutrition` | L1912 | `static func parseJSONNutrition(_ json: String) -> NutritionData?` |
| `parseRecipeFolder` | L922 (static) | `static func parseRecipeFolder(from:txn:) -> RecipeFolder?` |

`SearchIngredientProjection` struct — `private` в файле `RecipeYjsCodec.swift`.

`Self.isoTimestamp()` в `parseRecipeFolder` (L926) — заменить inline на `ISO8601DateFormatter().string(from: Date())` (actor-side `isoTimestamp()` остаётся для writers).

### 2. Зарегистрировать `RecipeYjsCodec.swift` в `project.pbxproj`

Проект использует классический pbxproj (НЕ `PBXFileSystemSynchronizedRootGroup`). Нужно 4 записи по образцу `RecipeEditPolicy.swift`:

1. **PBXBuildFile** section — новый UUID
2. **PBXFileReference** section — новый UUID
3. **Group membership** — в group `YjsSync` (рядом с `DocumentManager.swift`)
4. **PBXSourcesBuildPhase** — добавить build file

### 3. Схлопнуть `RecipeReader.swift`

- Удалить приватные `readName`, `readDescription`, `readNutrition`, `readIngredients`, `parseIngredient`, `parseJSONIngredients`.
- В `readFields` вызывать `RecipeYjsCodec.readRecipeName`, `RecipeYjsCodec.readDescription`, `RecipeYjsCodec.readIngredients(from:txn:version:preferArray: true)`, `RecipeYjsCodec.readNutrition`.
- Оставить: `parse(state:recipeId:)` (публичный API), `RecipeFields` struct, `formatAmount` (используется только в discover-проекции).

### 4. Фикс бага `hasQuantity`

Унифицировать на `!originalAmount.isEmpty || !amount.isEmpty` (web parity):

- `RecipeYjsCodec.parseIngredientMap` — было `hasOriginal && !originalAmount.isEmpty`
- `RecipeYjsCodec.parseJSONIngredients` — было `!originalAmount.isEmpty || !amount.isEmpty` (уже correct)
- Ожидается: после переезда `RecipeReader` будет использовать codec-версию, расхождение исчезнет.

### 5. Переключить call-сайты в `DocumentManager.swift`

| Call-сайт | Было | Стало |
|---|---|---|
| L212 в `readCollectionEntries` | `self.parseCollectionEntry(from: map, txn: txn)` | `RecipeYjsCodec.parseCollectionEntry(from: map, txn: txn)` |
| L257 в `readRecipeData` | `self.parseRecipeData(from: map, txn: txn, recipeId: recipeId)` | `RecipeYjsCodec.parseRecipeData(from: map, txn: txn, recipeId: recipeId)` |
| L321 в `readSearchIndex` | `self.readSearchIngredients(from: map, txn: txn, version: version)` | `RecipeYjsCodec.readSearchIngredients(from: map, txn: txn, version: version)` |
| L332 в `readSearchIndex` | `self.readDescription(from: map, txn: txn, version: version)` | `RecipeYjsCodec.readDescription(from: map, txn: txn, version: version)` |
| L554 в `moveIngredient` | `Self.parseIngredientMap(ingMap, txn: txn, fallbackOrder: fromIndex + 1)` | `RecipeYjsCodec.parseIngredientMap(ingMap, txn: txn, fallbackOrder: fromIndex + 1)` |
| L700 в `readFolders` | `Self.parseRecipeFolder(from: map, txn: txn)` | `RecipeYjsCodec.parseRecipeFolder(from: map, txn: txn)` |

### 6. Удалить 13 парсеров из `DocumentManager.swift`

- L1527–1544 — `parseCollectionEntry`
- L1546–1569 — `parseRecipeData`
- L1573–1583 — `readRecipeName`
- L1585–1601 — `readDescription`
- L1603–1606 — `SearchIngredientProjection` struct
- L1608–1639 — `readSearchIngredients`
- L1641–1672 — `searchIngredientsFromJSON`
- L1674–1694 — `readIngredients`
- L1696–1739 — `readNutrition`
- L1743–1770 — `parseIngredientMap` (static)
- L1863–1910 — `parseJSONIngredients`
- L1912–1927 — `parseJSONNutrition`
- L922–943 — `parseRecipeFolder` (static)

`isoTimestamp()` (L1772–1774) **ОСТАВЛЯЕМ** — используется writers.

### 7. Build + test + fix-until-green

- `xcodebuild build`
- `xcodebuild test`
- Если падает — loop `.agents/skills/fix-until-green/SKILL.md`

### 8. Commit + Linear

- Коммит в `master` (по workspace convention — small cleanups идут в master без feature branch)
- Закрыть Linear MIK-177/178/180/181
