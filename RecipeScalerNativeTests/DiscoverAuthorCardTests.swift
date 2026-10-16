import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

/// Spec 082 — `preview_recipes` decoding (FR-001, SC-003), the collage layout (FR-002),
/// photo URLs (FR-003) and the «Подборки» columns (FR-007).
@MainActor
final class DiscoverAuthorCardTests: XCTestCase {
    // MARK: - Decoding

    func testProfileDecodesPreviewRecipesInServerOrder() throws {
        let profile = try decodeProfile(previewRecipes: """
        "preview_recipes": [
          {"id": "r3", "name": "Шарлотка", "image_url": "/api/recipes/r3/image?size=card&v=c"},
          {"id": "r2", "name": "Борщ", "image_url": "/api/recipes/r2/image?size=card&v=b"},
          {"id": "r1", "name": "Блины", "image_url": "/api/recipes/r1/image?size=card&v=a"}
        ],
        """)

        XCTAssertEqual(profile.previewRecipes.map(\.id), ["r3", "r2", "r1"])
        XCTAssertEqual(profile.previewRecipes.first?.name, "Шарлотка")
        XCTAssertEqual(profile.previewRecipes.first?.imageUrl, "/api/recipes/r3/image?size=card&v=c")
        XCTAssertEqual(profile.recipeCount, 12)
    }

    func testProfileWithoutPreviewRecipesKeyDecodesAsEmpty() throws {
        // A server before 082 omits the key.
        let profile = try decodeProfile(previewRecipes: "")
        XCTAssertEqual(profile.previewRecipes, [])
        XCTAssertEqual(profile.username, "anna")
    }

    func testProfileWithEmptyPreviewRecipesDecodesAsEmpty() throws {
        let profile = try decodeProfile(previewRecipes: #""preview_recipes": [],"#)
        XCTAssertEqual(profile.previewRecipes, [])
    }

    func testProfileWithNullPreviewRecipesDecodesAsEmpty() throws {
        let profile = try decodeProfile(previewRecipes: #""preview_recipes": null,"#)
        XCTAssertEqual(profile.previewRecipes, [])
    }

    func testDiscoveryDataDecodesProfilesFromOldAndNewServers() throws {
        let json = """
        {
          "collections": [],
          "profiles": [
            {"username": "anna", "name": "Anna", "avatar_url": null, "recipe_count": 3, "description": null,
             "preview_recipes": [{"id": "r1", "name": "Блины", "image_url": "/api/recipes/r1/image?size=card&v=a"}]},
            {"username": "boris", "name": null, "avatar_url": null, "recipe_count": 1, "description": "Суп"}
          ]
        }
        """
        let data = try JSONDecoder().decode(DiscoveryDataDTO.self, from: Data(json.utf8))

        XCTAssertEqual(data.profiles.map(\.username), ["anna", "boris"])
        XCTAssertEqual(data.profiles[0].previewRecipes.map(\.id), ["r1"])
        XCTAssertEqual(data.profiles[1].previewRecipes, [])
    }

    func testMemberwiseInitDefaultsPreviewRecipesToEmpty() {
        let profile = PublicProfilePreviewDTO(
            username: "anna",
            name: "Anna",
            avatarURL: nil,
            recipeCount: 0,
            description: nil
        )
        XCTAssertEqual(profile.previewRecipes, [])
    }

    // MARK: - Collage layout

    func testCollageLayoutByPhotoCount() {
        XCTAssertEqual(DiscoverAuthorCollageLayout(photoCount: 0), .placeholder)
        XCTAssertEqual(DiscoverAuthorCollageLayout(photoCount: 1), .single)
        XCTAssertEqual(DiscoverAuthorCollageLayout(photoCount: 2), .halves)
        XCTAssertEqual(DiscoverAuthorCollageLayout(photoCount: 3), .featureAndStack)
        // The server sends at most three; more still shows the first three.
        XCTAssertEqual(DiscoverAuthorCollageLayout(photoCount: 4), .featureAndStack)
        XCTAssertEqual(DiscoverAuthorCollageLayout(photoCount: 4).photoCount, 3)
        XCTAssertEqual(DiscoverAuthorCollageLayout(photoCount: 0).photoCount, 0)
    }

    func testCollageTileFrames() {
        let size = CGSize(width: 303, height: 170.4375)
        let gap = DiscoverAuthorCollageLayout.gap

        XCTAssertEqual(DiscoverAuthorCollageLayout.placeholder.tileFrames(in: size), [])
        XCTAssertEqual(DiscoverAuthorCollageLayout.single.tileFrames(in: size), [CGRect(origin: .zero, size: size)])

        let halves = DiscoverAuthorCollageLayout.halves.tileFrames(in: size)
        XCTAssertEqual(halves.count, 2)
        XCTAssertEqual(halves[0].width, 150, accuracy: 0.001)
        XCTAssertEqual(halves[1].minX - halves[0].maxX, gap, accuracy: 0.001)
        XCTAssertEqual(halves[1].maxX, size.width, accuracy: 0.001)

        let stack = DiscoverAuthorCollageLayout.featureAndStack.tileFrames(in: size)
        XCTAssertEqual(stack.count, 3)
        // The newest photo: 2/3 of the width without the gap, the full height.
        XCTAssertEqual(stack[0].width, 200, accuracy: 0.001)
        XCTAssertEqual(stack[0].height, size.height, accuracy: 0.001)
        XCTAssertEqual(stack[1].minX - stack[0].maxX, gap, accuracy: 0.001)
        XCTAssertEqual(stack[1].width, 100, accuracy: 0.001)
        XCTAssertEqual(stack[2].minY - stack[1].maxY, gap, accuracy: 0.001)
        XCTAssertEqual(stack[2].maxY, size.height, accuracy: 0.001)
        XCTAssertEqual(stack[1].height, stack[2].height, accuracy: 0.001)
    }

    // MARK: - Photo URL, name, VoiceOver

    func testPreviewRecipeImageURLResolvesRelativeAgainstBaseURL() {
        let relative = DiscoverPreviewRecipeDTO(id: "r1", name: "Блины", imageUrl: "/api/recipes/r1/image?size=card&v=a")
        XCTAssertEqual(
            DiscoverImageURLs.authorPreviewRecipe(relative)?.absoluteString,
            "\(Config.baseURL)/api/recipes/r1/image?size=card&v=a"
        )

        let absolute = DiscoverPreviewRecipeDTO(id: "r2", name: "Борщ", imageUrl: "https://cdn.example.com/r2.webp")
        XCTAssertEqual(DiscoverImageURLs.authorPreviewRecipe(absolute)?.absoluteString, "https://cdn.example.com/r2.webp")
    }

    func testDisplayNameFallsBackToUsername() {
        XCTAssertEqual(DiscoverAuthorCard.displayName(for: makeProfile(name: "Anna")), "Anna")
        XCTAssertEqual(DiscoverAuthorCard.displayName(for: makeProfile(name: nil)), "@anna")
        XCTAssertEqual(DiscoverAuthorCard.displayName(for: makeProfile(name: "  ")), "@anna")
    }

    func testAccessibilityLabelIsNameAndRecipeCount() {
        let profile = makeProfile(name: "Anna", recipeCount: 5)
        let count = Bundle.appPluralizedString(key: "discover.profile.recipe-count", count: 5)
        XCTAssertEqual(DiscoverAuthorCard.accessibilityLabel(for: profile), "Anna, \(count)")
    }

    // MARK: - «Подборки» columns

    func testColumnCount() {
        func count(_ mode: AppLayoutMode, landscape: Bool, sidebar: Bool) -> Int {
            DiscoverRootGridLayout.columnCount(layoutMode: mode, isLandscapeViewport: landscape, sidebarShown: sidebar)
        }
        XCTAssertEqual(count(.phone, landscape: true, sidebar: false), 1)
        XCTAssertEqual(count(.padRegular, landscape: false, sidebar: false), 2)
        XCTAssertEqual(count(.padRegular, landscape: false, sidebar: true), 2)
        XCTAssertEqual(count(.padRegular, landscape: true, sidebar: true), 2)
        XCTAssertEqual(count(.padRegular, landscape: true, sidebar: false), 3)
    }

    func testGridColumns() {
        let authors = DiscoverRootGridLayout.authorColumns(count: 3)
        XCTAssertEqual(authors.count, 3)
        XCTAssertEqual(authors[0].spacing, 18)
        let collections = DiscoverRootGridLayout.collectionColumns(count: 2)
        XCTAssertEqual(collections.count, 2)
        XCTAssertEqual(collections[0].spacing, 28)
    }

    // MARK: - Helpers

    // MARK: - Caption

    private let caption = "Галеты с овощами · Говяжий бульон · Гёзлеме с сыром"

    func testCaptionThatFitsIsShownWhole() {
        let text = DiscoverAuthorCaption.fitted(caption, recipeCount: 3, moreFormat: "%@ и др.") { _ in true }
        XCTAssertEqual(text, caption)
    }

    func testCaptionKeepsWholeNamesThatFitAndAddsMore() {
        let text = DiscoverAuthorCaption.fitted(caption, recipeCount: 3, moreFormat: "%@ и др.") {
            $0.count <= 45
        }
        XCTAssertEqual(text, "Галеты с овощами · Говяжий бульон и др.")
    }

    func testCaptionWithFewerNamesThanRecipesAddsMore() {
        let text = DiscoverAuthorCaption.fitted(caption, recipeCount: 25, moreFormat: "%@ и др.") { _ in true }
        XCTAssertEqual(text, caption + " и др.")
    }

    func testCaptionFallsBackToFirstNameWhenNothingFits() {
        let text = DiscoverAuthorCaption.fitted(caption, recipeCount: 3, moreFormat: "%@ и др.") { _ in false }
        XCTAssertEqual(text, "Галеты с овощами и др.")
    }

    func testBodyMeasurementCountsLines() {
        XCTAssertTrue(DiscoverAuthorCaption.fitsBody("Борщ", width: 300, maxLines: 1))
        XCTAssertFalse(DiscoverAuthorCaption.fitsBody(caption, width: 120, maxLines: 1))
        XCTAssertTrue(DiscoverAuthorCaption.fitsBody(caption, width: 2_000, maxLines: 1))
    }

    private func decodeProfile(previewRecipes: String) throws -> PublicProfilePreviewDTO {
        let json = """
        {
          "username": "anna",
          "name": "Anna",
          "avatar_url": "/api/users/anna/avatar",
          \(previewRecipes)
          "recipe_count": 12,
          "description": "Блины · Борщ"
        }
        """
        return try JSONDecoder().decode(PublicProfilePreviewDTO.self, from: Data(json.utf8))
    }

    private func makeProfile(name: String?, recipeCount: Int = 1) -> PublicProfilePreviewDTO {
        PublicProfilePreviewDTO(
            username: "anna",
            name: name,
            avatarURL: nil,
            recipeCount: recipeCount,
            description: nil
        )
    }
}
