# План реализации: сохранение нечисловых количеств ингредиентов в нативном экспорте (v1.4 + amountText)

**Spec**: [spec.md](spec.md)
**Подход**: TDD — тесты сначала, потом реализация, потом `fix-until-green`.

## Этапы

### 1. Wire format types (`NativeFormatTypes.swift`)

- Добавить `NativeIngredient.amountText: String?`.
- Synthesized `Codable` — `amountText` optional, `nil` пропускается при encode/decode.

### 2. JSON schema (`schemas/export-schema-v1.4.json`)

- В `recipes.items.ingredients.items.properties` добавить:

```json
"amountText": {
  "type": "string",
  "description": "Raw non-numeric amount (e.g. '1/2', '2-3', 'to taste'). Optional v1.4 extension; older readers ignore it.",
  "maxLength": 64
}
```

- Wire-формат остаётся v1.4 — отдельная schema v1.5 не нужна.

### 3. Validator (`NativeFormatValidator.swift`)

- Для каждого ингредиента: если `amountText != nil` — проверить, что trim непустой и ≤ 64 символов.
- Безусловная валидация (не привязана к версии).

### 4. Export side

**`NativeRecipeExporter.swift`**:
- `ExportIngredient`: добавить `amountText: String?` (Sendable, default `nil`).
- `buildPayload`:
  - Прокидывать `amountText` в `NativeIngredient`.
  - `metadata.version = "1.4"`, `metadata.type = "recipes-v1.4"`.

**`NativeExportImportService.swift`**:
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

### 5. Import side (`DocumentManager.swift`)

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

Это автоматически попадает в правильную ветку `addIngredient`, которая уже пишет `.string(...)` для нечисловых.

### 6. Тесты (TDD)

См. таблицу в [spec.md](spec.md).

### 7. Build + test

`fix-until-green` — `xcodebuild build` + `xcodebuild test` (см. `docs/AGENT-WORKFLOW.md`).

### 8. Документация

- Обновить `specs/029-account-data-export-import/spec.md` — changelog: v1.4 + amountText extension field.
