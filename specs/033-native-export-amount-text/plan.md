# План реализации: сохранение нечисловых количеств ингредиентов в нативном экспорте (v1.5)

**Spec**: [spec.md](spec.md)
**Подход**: TDD — тесты сначала, потом реализация, потом `fix-until-green`.

## Этапы

### 1. Wire format types (`NativeFormatTypes.swift`)

- Добавить `NativeIngredient.amountText: String?`.
- Реализовать **custom `Codable`** для `NativeIngredient`:
  - `init(from:)`: `originalAmount` декодируется через `AnyCodableValue` (или nested `decodeIfPresent` с try/catch для `Double`, потом для `String`). Если пришла строка — кладётся в `amountText`, `originalAmount = nil`.
  - `encode(to:)`: кодирует `originalAmount` (если есть) и `amountText` (если есть). В обоих случаях опускает `nil`-поля.
- `NativeRecipe`: добавить `amountText` поле не нужно — оно уже на уровне ингредиента.

### 2. Format version (`NativeFormatVersion.swift`)

- Добавить `case v1_5 = "1.5"`.
- `typeString`: `.v1_5 → "recipes-v1.5"`.
- `supportsAmountText: Bool { self >= .v1_5 }`.
- `sortOrder`: `v1_5 = 5`.
- В `normalizeNativeFormatVersion`: добавить `case "recipes-v1.5": return .v1_5`.

### 3. JSON schema (`schemas/export-schema-v1.5.json`)

- Копия `export-schema-v1.4.json`.
- В `recipes.items.ingredients.items.properties` добавить:

```json
"amountText": {
  "type": "string",
  "description": "Raw non-numeric amount (e.g. '1/2', '2-3', 'to taste')",
  "maxLength": 64
}
```

- В `metadata.version.enum`: `["1.5"]`.
- В `metadata.type.enum`: `["recipes-v1.5"]`.

### 4. Validator (`NativeFormatValidator.swift`)

- v1.5 type check (как для v1.2+).
- Для каждого ингредиента (v1.5+): если `amountText != nil` — проверить, что trim непустой и ≤ 64 символов.

### 5. Export side

**`NativeRecipeExporter.swift`**:
- `ExportIngredient`: добавить `amountText: String?` (Sendable, default `nil`).
- `buildPayload`:
  - Прокидывать `amountText` в `NativeIngredient`.
  - Менять `metadata.version = "1.5"`, `metadata.type = "recipes-v1.5"`.

**`NativeExportImportService.swift:79-88`**:
```swift
ingredients: recipeData.ingredients.map { ing in
    let numeric = ing.numericValue
    let rawText = ing.originalAmount.isEmpty ? ing.amount : ing.originalAmount
    let shouldEmitText = (numeric == nil) && ing.hasQuantity && !rawText.isEmpty
    return ExportIngredient(
        id: ing.id,
        name: ing.name,
        originalAmount: numeric,
        amountText: shouldEmitText ? rawText : nil,
        unit: ing.unit.isEmpty ? nil : ing.unit,
        order: ing.order,
        isSeparator: ing.isSeparator ? true : nil
    )
}
```

### 6. Import side (`DocumentManager.swift:1055-1087`)

```swift
let originalAmount: Double? = ingredient.originalAmount
let amountText: String? = ingredient.amountText?.trimmingCharacters(in: .whitespacesAndNewlines)
let unit = ingredient.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

let hasQuantity: Bool
let amountString: String
if let oa = originalAmount {
    hasQuantity = true
    amountString = String(oa)
} else if let text = amountText, !text.isEmpty {
    hasQuantity = true
    amountString = text
} else {
    hasQuantity = false
    amountString = ""
}
```

Это автоматически попадает в правильную ветку `addIngredient` (1755-1765), которая уже пишет `.string(...)` для нечисловых.

### 7. Тесты (TDD)

См. таблицу в [spec.md](spec.md).

### 8. Build + test

`fix-until-green` — `xcodebuild build` + `xcodebuild test` (см. `docs/AGENT-WORKFLOW.md`).

### 9. Документация

- Обновить `specs/029-account-data-export-import/spec.md` (если упоминается формат) — указать v1.5 как текущий.
