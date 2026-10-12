//
//  RecipesSelectionTests.swift
//
//  Spec 081 (T009, plan.md Р4) — path ↔ selection of the Recipes section.
//

import XCTest
@testable import RecipeScalerNative

final class RecipesSelectionTests: XCTestCase {

    private let allRecipes = CollectionVirtualFolders.allRecipesFolderId

    func testPathRoundTrip() {
        let canonicalPaths: [[RecipesRoute]] = [
            [],
            [.folder("f1")],
            [.recipe(recipeId: "r1", folderContext: nil)],
            [.folder("f1"), .recipe(recipeId: "r1", folderContext: "f1")],
            [.folder(allRecipes), .recipe(recipeId: "r2", folderContext: nil)],
            [.recipe(recipeId: "r3", folderContext: nil, openInEditMode: true)],
        ]
        for path in canonicalPaths {
            let selection = RecipesSelection.selection(from: path)
            XCTAssertEqual(RecipesSelection.path(for: selection), path, "\(path)")
            XCTAssertEqual(
                RecipesSelection.selection(from: RecipesSelection.path(for: selection)),
                selection,
                "\(path)"
            )
        }

        XCTAssertEqual(
            RecipesSelection.selection(from: [.folder("f1"), .recipe(recipeId: "r1", folderContext: "f1")]),
            RecipesSelection(collectionId: "f1", recipeId: "r1", recipeFolderContext: "f1")
        )
        XCTAssertEqual(RecipesSelection.selection(from: []), RecipesSelection())
    }

    /// A deeper iPhone stack (drill into two folders, open two recipes) reads as the
    /// last folder and the last recipe.
    func testSelectionReadsLastFolderAndLastRecipe() {
        let phonePath: [RecipesRoute] = [
            .folder("f1"),
            .recipe(recipeId: "r1", folderContext: "f1"),
            .folder("f2"),
            .recipe(recipeId: "r2", folderContext: "f2", openInEditMode: true),
        ]
        XCTAssertEqual(
            RecipesSelection.selection(from: phonePath),
            RecipesSelection(collectionId: "f2", recipeId: "r2", recipeFolderContext: "f2", openInEditMode: true)
        )
    }

    func testSelectingCollectionOpensFirstRecipe() {
        XCTAssertEqual(
            RecipesSelection.selectingCollection("f1", firstRecipeId: "r1", folderContext: "f1"),
            [.folder("f1"), .recipe(recipeId: "r1", folderContext: "f1")]
        )
        XCTAssertEqual(
            RecipesSelection.selectingCollection("f1", firstRecipeId: nil, folderContext: "f1"),
            [.folder("f1")],
            "an empty collection selects only the folder"
        )

        // Picking another row keeps the collection and drops edit mode of the previous recipe.
        let inCollection: [RecipesRoute] = [
            .folder("f1"),
            .recipe(recipeId: "r1", folderContext: "f1", openInEditMode: true),
        ]
        XCTAssertEqual(
            RecipesSelection.selectingRecipe("r2", in: inCollection, folderContext: "f1"),
            [.folder("f1"), .recipe(recipeId: "r2", folderContext: "f1")]
        )
        XCTAssertEqual(
            RecipesSelection.selectingRecipe("r2", in: []),
            [.recipe(recipeId: "r2", folderContext: nil)]
        )
        XCTAssertEqual(
            RecipesSelection.selectingRecipe("r2", in: [], openInEditMode: true),
            [.recipe(recipeId: "r2", folderContext: nil, openInEditMode: true)]
        )
    }

    /// iPhone pushes → iPad reads → iPad writes → iPhone sees the same stack (FR-018).
    func testSelectionSurvivesModeSwitch() {
        // Phone: drill into a collection, open a recipe in edit mode.
        var recipesPath: [RecipesRoute] = []
        recipesPath.append(.folder("f1"))
        recipesPath.append(.recipe(recipeId: "r1", folderContext: "f1", openInEditMode: true))

        // Window widens: the iPad columns read the same array.
        let onPad = RecipesSelection.selection(from: recipesPath)
        XCTAssertEqual(onPad.collectionId, "f1")
        XCTAssertEqual(onPad.recipeId, "r1")
        XCTAssertTrue(onPad.openInEditMode)

        // The iPad writes its canonical path back; narrowing again shows the phone stack unchanged.
        recipesPath = RecipesSelection.path(for: onPad)
        XCTAssertEqual(recipesPath, [.folder("f1"), .recipe(recipeId: "r1", folderContext: "f1", openInEditMode: true)])

        // iPad picks another recipe in the flat list → the phone shows it on top of the list.
        recipesPath = RecipesSelection.selectingRecipe("r2", in: [])
        XCTAssertEqual(RecipesSelection.selection(from: recipesPath), RecipesSelection(recipeId: "r2"))
        XCTAssertEqual(recipesPath, [.recipe(recipeId: "r2", folderContext: nil)])
    }

    func testDeletedSelectionFallsBack() {
        let before = ["r1", "r2", "r3", "r4"]

        // Open recipe deleted on another device → the next one in the list, edit mode dropped.
        let editingR2 = RecipesSelection(recipeId: "r2", openInEditMode: true)
        XCTAssertEqual(
            RecipesSelection.resolvingDeletions(
                editingR2, userFolderIds: [], recipeIds: ["r1", "r3", "r4"], previousRecipeIds: before
            ),
            RecipesSelection(recipeId: "r3")
        )
        // The last one deleted → the one before it.
        XCTAssertEqual(
            RecipesSelection.resolvingDeletions(
                RecipesSelection(recipeId: "r4"), userFolderIds: [], recipeIds: ["r1", "r2", "r3"],
                previousRecipeIds: before
            ).recipeId,
            "r3"
        )
        // Several gone at once → the nearest next survivor.
        XCTAssertEqual(
            RecipesSelection.resolvingDeletions(
                RecipesSelection(recipeId: "r2"), userFolderIds: [], recipeIds: ["r1", "r4"],
                previousRecipeIds: before
            ).recipeId,
            "r4"
        )
        // Not in the previous list either → the first recipe.
        XCTAssertEqual(
            RecipesSelection.resolvingDeletions(
                RecipesSelection(recipeId: "gone"), userFolderIds: [], recipeIds: ["r1", "r3"],
                previousRecipeIds: []
            ).recipeId,
            "r1"
        )
        // Nothing left → no recipe, no crash.
        XCTAssertNil(
            RecipesSelection.resolvingDeletions(
                RecipesSelection(recipeId: "r1"), userFolderIds: [], recipeIds: [], previousRecipeIds: ["r1"]
            ).recipeId
        )

        // Selected collection deleted (or unknown) → «Все рецепты»; the open recipe stays if it exists.
        let inCollection = RecipesSelection(collectionId: "f1", recipeId: "r1", recipeFolderContext: "f1")
        XCTAssertEqual(
            RecipesSelection.resolvingDeletions(
                inCollection, userFolderIds: ["f2"], recipeIds: before, previousRecipeIds: ["r1"]
            ),
            RecipesSelection(recipeId: "r1")
        )
        // Existing user collections and virtual folders are kept.
        XCTAssertEqual(
            RecipesSelection.resolvingDeletions(
                inCollection, userFolderIds: ["f1"], recipeIds: before, previousRecipeIds: before
            ),
            inCollection
        )
        let virtual = RecipesSelection(collectionId: allRecipes, recipeId: "r1")
        XCTAssertEqual(
            RecipesSelection.resolvingDeletions(virtual, userFolderIds: [], recipeIds: before, previousRecipeIds: before),
            virtual
        )
        // Nothing selected stays nothing selected (the first-recipe rule belongs to the iPad list, T028).
        XCTAssertEqual(
            RecipesSelection.resolvingDeletions(RecipesSelection(), userFolderIds: [], recipeIds: before, previousRecipeIds: before),
            RecipesSelection()
        )
    }

    // MARK: - iPad split (T028)

    /// «Все рецепты» (title menu, sidebar row) keeps the open recipe and drops edit mode.
    func testSelectingAllRecipesKeepsOpenRecipe() {
        XCTAssertEqual(
            RecipesSelection.selectingAllRecipes(in: [
                .folder("f1"),
                .recipe(recipeId: "r1", folderContext: "f1", openInEditMode: true),
            ]),
            [.recipe(recipeId: "r1", folderContext: nil)]
        )
        XCTAssertEqual(RecipesSelection.selectingAllRecipes(in: [.folder("f1")]), [])
        XCTAssertEqual(RecipesSelection.selectingAllRecipes(in: []), [])
    }

    /// Pinned first: the lists below are given in the order the column shows them.
    private let lists: [String?: [String]] = [
        nil: ["pinned", "r1", "r2", "r3"],
        "f1": ["r2", "r3"],
        "empty": [],
    ]

    private func repaired(
        _ path: [RecipesRoute],
        userFolderIds: [String] = ["f1", "empty"],
        live: Set<String>? = nil,
        previousLive: Set<String> = [],
        lists: [String?: [String]]? = nil,
        previousList: [String] = []
    ) -> [RecipesRoute]? {
        let lists = lists ?? self.lists
        return RecipesSelection.splitRepairedPath(
            path,
            userFolderIds: userFolderIds,
            liveRecipeIds: live ?? Set(lists[nil] ?? []),
            previousLiveRecipeIds: previousLive,
            listRecipeIds: { lists[$0] ?? [] },
            previousListRecipeIds: previousList
        )
    }

    func testSplitOpensFirstRecipeWhenNothingIsOpen() {
        XCTAssertEqual(repaired([]), [.recipe(recipeId: "pinned", folderContext: nil)])
        XCTAssertEqual(
            repaired([.folder("f1")]),
            [.folder("f1"), .recipe(recipeId: "r2", folderContext: "f1")]
        )
        XCTAssertNil(repaired([.folder("empty")]), "an empty collection keeps the panel empty")
        XCTAssertNil(repaired([], lists: [nil: []]), "no recipes at all")
    }

    func testSplitKeepsCanonicalSelection() {
        XCTAssertNil(repaired([.recipe(recipeId: "r1", folderContext: nil)]))
        XCTAssertNil(repaired([.folder("f1"), .recipe(recipeId: "r3", folderContext: "f1", openInEditMode: true)]))
        XCTAssertNil(repaired([.folder(allRecipes), .recipe(recipeId: "r1", folderContext: nil)]))
        // Just created: not in the index yet, never was → stays open.
        XCTAssertNil(repaired([.folder("f1"), .recipe(recipeId: "new", folderContext: "f1", openInEditMode: true)]))
        // Removed from the collection but still alive → stays open in that collection.
        XCTAssertNil(repaired([.folder("f1"), .recipe(recipeId: "r1", folderContext: "f1")]))
    }

    /// Spotlight, Universal Links, quick actions and import push `.recipe` over the
    /// current path; the split makes it canonical so the row is highlighted.
    func testSplitCanonicalizesDeepLinks() {
        // Outside the selected collection → «Все рецепты».
        XCTAssertEqual(
            repaired([.folder("f1"), .recipe(recipeId: "r2", folderContext: "f1"), .recipe(recipeId: "r1", folderContext: nil)]),
            [.recipe(recipeId: "r1", folderContext: nil)]
        )
        // Inside it → stays in the collection.
        XCTAssertEqual(
            repaired([.folder("f1"), .recipe(recipeId: "r2", folderContext: "f1"), .recipe(recipeId: "r3", folderContext: nil)]),
            [.folder("f1"), .recipe(recipeId: "r3", folderContext: nil)]
        )
        // `handleDeepLink` resets the path first: already canonical.
        XCTAssertNil(repaired([.recipe(recipeId: "r3", folderContext: nil)]))
    }

    func testSplitRepairsDeletions() {
        // The open recipe was deleted on another device → the next one, edit mode dropped.
        XCTAssertEqual(
            repaired(
                [.recipe(recipeId: "r2", folderContext: nil, openInEditMode: true)],
                live: ["pinned", "r1", "r3"],
                previousLive: ["pinned", "r1", "r2", "r3"],
                lists: [nil: ["pinned", "r1", "r3"]],
                previousList: ["pinned", "r1", "r2", "r3"]
            ),
            [.recipe(recipeId: "r3", folderContext: nil)]
        )
        // Last in the collection → the one before it.
        XCTAssertEqual(
            repaired(
                [.folder("f1"), .recipe(recipeId: "r3", folderContext: "f1")],
                live: ["pinned", "r1", "r2"],
                previousLive: ["pinned", "r1", "r2", "r3"],
                lists: [nil: ["pinned", "r1", "r2"], "f1": ["r2"]],
                previousList: ["r2", "r3"]
            ),
            [.folder("f1"), .recipe(recipeId: "r2", folderContext: "f1")]
        )
        // The collection was deleted → «Все рецепты», the recipe stays open.
        XCTAssertEqual(
            repaired([.folder("gone"), .recipe(recipeId: "r2", folderContext: "gone")]),
            [.recipe(recipeId: "r2", folderContext: nil)]
        )
        // The collection was deleted with nothing open → «Все рецепты» and its first recipe.
        XCTAssertEqual(repaired([.folder("gone")]), [.recipe(recipeId: "pinned", folderContext: nil)])
    }
}
