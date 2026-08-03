//
//  UTType+RecipeScaler.swift
//  RecipeScalerCore
//
//  Custom UTType for the Recipe Scaler native recipe file format.
//  Registered in the main app's Info.plist via `UTExportedTypeDeclarations`
//  (identifier `ru.recipescaler.recipe`, extension `.recipe`).
//
//  The on-disk payload is a ZIP archive conforming to the Recipe Scaler v1.4
//  format: `recipes.json` at the root, optionally `images/<recipeId>/full.webp`
//  + `images/<recipeId>/preview.webp`. Conforming to `public.zip-archive`
//  means older Recipe Scaler builds (and any zip reader) can still open the
//  file, while the custom extension lets iOS route AirDrop/Mail/Files
//  payloads to Recipe Scaler without polluting the «Open in…» list for
//  every generic .zip file.
//

import UniformTypeIdentifiers

public extension UTType {
    /// Recipe Scaler's own recipe file type.
    ///
    /// Resolved via `init(exportedAs:conformingTo:)` — that call succeeds on
    /// any OS version (it doesn't require the type to be installed), and on
    /// devices where Recipe Scaler's `UTExportedTypeDeclarations` is
    /// registered (the main app is installed), iOS will report our bundle as
    /// the owner and use our icon in share sheets.
    static let recipeScalerRecipe = UTType(
        exportedAs: "ru.recipescaler.recipe",
        conformingTo: .zip
    )
}
