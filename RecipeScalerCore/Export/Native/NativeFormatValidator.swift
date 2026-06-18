import Foundation

/// Validate a parsed export payload against the expected schema for its version.
public enum NativeFormatValidator {

    /// Maximum allowed length (in characters) of `NativeIngredient.amountText`.
    /// Reasonable upper bound for a quantity string; anything longer is suspicious.
    public static let maxAmountTextLength = 64

    /// Validate the payload and return a list of errors.
    /// Structural errors are fatal; per-recipe/folder errors allow partial import.
    public static func validate(
        payload: NativeExportPayload,
        version: NativeFormatVersion
    ) -> NativeValidationResult {
        var structuralErrors: [String] = []
        var recipeErrors: [(index: Int, errors: [String])] = []
        var folderErrors: [(index: Int, errors: [String])] = []

        // --- Structural validation ---

        if version == .v1_0 {
            // v1.0: metadata may be absent; recipes array required
            if payload.recipes.isEmpty {
                structuralErrors.append("recipes array is empty")
            }
        } else {
            // v1.1+: metadata required
            let meta = payload.metadata
            if meta.version.isEmpty {
                structuralErrors.append("metadata.version is required")
            }
            if meta.exportDate.isEmpty {
                structuralErrors.append("metadata.exportDate is required")
            }
            if meta.count != nil && meta.count! < 0 {
                structuralErrors.append("metadata.count must be >= 0")
            }
            // type check for v1.2+
            if version >= .v1_2 {
                if let expectedType = version.typeString,
                   let actualType = meta.type,
                   actualType != expectedType {
                    structuralErrors.append("metadata.type expected '\(expectedType)', got '\(actualType)'")
                }
            }
        }

        // --- Per-recipe validation ---

        for (index, recipe) in payload.recipes.enumerated() {
            var errors: [String] = []

            if recipe.id.isEmpty {
                errors.append("id is required")
            }
            if recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("name is required")
            }

            // v1.3+: servings must be positive if present
            if version >= .v1_3, let servings = recipe.servings, servings < 0 {
                errors.append("servings must be >= 0")
            }

            // v1.2+: nutrition validation
            if version >= .v1_2, let nutrition = recipe.nutrition {
                if let cal = nutrition.calories, cal < 0 {
                    errors.append("nutrition.calories must be >= 0")
                }
                if let p = nutrition.protein, p < 0 {
                    errors.append("nutrition.protein must be >= 0")
                }
                if let f = nutrition.fat, f < 0 {
                    errors.append("nutrition.fat must be >= 0")
                }
                if let c = nutrition.carbs, c < 0 {
                    errors.append("nutrition.carbs must be >= 0")
                }
            }

            // v1.4+: folderIds must be non-empty strings
            if version >= .v1_4, let folderIds = recipe.folderIds {
                for fid in folderIds {
                    if fid.isEmpty {
                        errors.append("folderIds must not contain empty strings")
                        break
                    }
                }
            }

            // v1.5+: amountText validation (non-numeric ingredient amounts).
            if version >= .v1_5 {
                for (ingIndex, ingredient) in recipe.ingredients.enumerated() {
                    if let text = ingredient.amountText {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            errors.append("recipe[\(index)].ingredients[\(ingIndex)].amountText must be non-empty")
                        } else if trimmed.count > Self.maxAmountTextLength {
                            errors.append("recipe[\(index)].ingredients[\(ingIndex)].amountText exceeds \(Self.maxAmountTextLength) characters")
                        }
                    }
                }
            }

            if !errors.isEmpty {
                recipeErrors.append((index, errors))
            }
        }

        // --- Per-folder validation (v1.4+) ---

        if version >= .v1_4, let folders = payload.folders {
            for (index, folder) in folders.enumerated() {
                var errors: [String] = []

                if folder.id.isEmpty {
                    errors.append("id is required")
                }
                if folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("name is required")
                }

                if !errors.isEmpty {
                    folderErrors.append((index, errors))
                }
            }
        }

        return NativeValidationResult(
            structuralErrors: structuralErrors,
            recipeErrors: recipeErrors,
            folderErrors: folderErrors
        )
    }
}
