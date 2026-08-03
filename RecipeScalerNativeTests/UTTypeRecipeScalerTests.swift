//
//  UTTypeRecipeScalerTests.swift
//
//  Spec 057 T004 — verifies the custom UTType registration for the
//  `.recipe` file format declared in Info.plist via UTExportedTypeDeclarations.
//

import XCTest
import UniformTypeIdentifiers
@testable import RecipeScalerCore

final class UTTypeRecipeScalerTests: XCTestCase {

    func test_staticConstant_resolvesWithIdentifier() {
        XCTAssertEqual(UTType.recipeScalerRecipe.identifier, "ru.recipescaler.recipe")
    }

    func test_lookupByIdentifier_returnsSameType() {
        let lookedUp = UTType("ru.recipescaler.recipe")
        XCTAssertEqual(lookedUp, UTType.recipeScalerRecipe)
    }

    func test_conformsToZipArchive() {
        // `.recipe` files are ZIP archives of the v1.4 format.
        // `UTType.zip` is `public.zip-archive`.
        XCTAssertTrue(UTType.recipeScalerRecipe.conforms(to: .zip))
    }

    func test_declaresRecipeFilenameExtension() {
        // The static type registered in Info.plist must own the `.recipe` extension.
        let extensions = UTType.recipeScalerRecipe.tags[.filenameExtension] ?? []
        XCTAssertTrue(extensions.contains("recipe"),
                      "Expected `.recipe` in \(extensions)")
    }

    func test_filenameExtensionLookup_resolvesToOurType() {
        // iOS resolves file extensions to UTTypes at runtime. In the test
        // process the type declared in the host app's Info.plist is visible
        // because the test bundle is loaded into the app's process space.
        let resolved = UTType(filenameExtension: "recipe")
        XCTAssertEqual(resolved, UTType.recipeScalerRecipe)
    }
}
