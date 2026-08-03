//
//  RecipeImportContentTypes.swift
//  RecipeScalerCore
//

import UniformTypeIdentifiers

public enum RecipeImportContentTypes {
    public static var supported: [UTType] {
        var types: [UTType] = [.json, .zip, .data, UTType.recipeScalerRecipe]
        if let paprikaArchive = UTType(filenameExtension: "paprikarecipes") {
            types.append(paprikaArchive)
        }
        if let paprikaSingle = UTType(filenameExtension: "paprikarecipe") {
            types.append(paprikaSingle)
        }
        if let crumb = UTType(filenameExtension: "crumb") {
            types.append(crumb)
        }
        return types
    }
}
