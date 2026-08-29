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

/// Recipe file type identifier, flavor-dependent (spec 066).
///
/// The prod app exports `ru.recipescaler.recipe`; the side-by-side dev build
/// exports `ru.recipescaler.recipe.debug` so AirDrop / «Open in…» routes
/// files to the intended install. The value must match the main target's
/// `UTExportedTypeDeclarations` in Info.plist (`$(RS_RECIPE_UTTYPE)`) and the
/// `RS_RECIPE_UTTYPE` build setting of the active configuration.
public enum RecipeScalerFlavor {
    public static let recipeUTTypeIdentifier: String = {
        #if RS_DEV_FLAVOR
        return "ru.recipescaler.recipe.debug"
        #else
        return "ru.recipescaler.recipe"
        #endif
    }()

    /// Asset catalog logo for splash, auth, and widget chrome (spec 066).
    public static let appLogoAssetName: String = {
        #if RS_DEV_FLAVOR
        return "AppLogoDev"
        #else
        return "AppLogo"
        #endif
    }()
}

public extension UTType {
    /// Recipe Scaler's own recipe file type.
    ///
    /// Resolved via `init(exportedAs:conformingTo:)` — that call succeeds on
    /// any OS version (it doesn't require the type to be installed), and on
    /// devices where Recipe Scaler's `UTExportedTypeDeclarations` is
    /// registered (the main app is installed), iOS will report our bundle as
    /// the owner and use our icon in share sheets.
    static let recipeScalerRecipe = UTType(
        exportedAs: RecipeScalerFlavor.recipeUTTypeIdentifier,
        conformingTo: .zip
    )
}
