import UIKit
import XCTest
import YrsC
@testable import RecipeScalerNative

final class RecipeScalerNativeTests: XCTestCase {
    func testUserSettingsDecodesVkusvillEnabled() throws {
        let data = try XCTUnwrap(
            "{\"nutritionEnabled\":false,\"vkusvillEnabled\":true}".data(using: .utf8)
        )

        let settings = try JSONDecoder().decode(UserSettingsDTO.self, from: data)

        XCTAssertEqual(settings.vkusvillEnabled, true)
    }

    func testVkusvillBuyButtonVisibilityRequiresEnabledRussianLocale() {
        XCTAssertTrue(VkusvillUIVisibility.showsBuyButton(enabled: true, localeIdentifier: "ru"))
        XCTAssertTrue(VkusvillUIVisibility.showsBuyButton(enabled: true, localeIdentifier: "ru-RU"))
        XCTAssertFalse(VkusvillUIVisibility.showsBuyButton(enabled: false, localeIdentifier: "ru"))
        XCTAssertFalse(VkusvillUIVisibility.showsBuyButton(enabled: true, localeIdentifier: "en"))
        XCTAssertFalse(VkusvillUIVisibility.showsBuyButton(enabled: true, localeIdentifier: nil))
    }

    func testRecipeEditPolicyV3Only() {
        XCTAssertTrue(RecipeEditPolicy.supportsEditFormat(version: "3"))
        XCTAssertFalse(RecipeEditPolicy.supportsEditFormat(version: "1"))
        XCTAssertFalse(RecipeEditPolicy.supportsEditFormat(version: "2"))
        XCTAssertFalse(RecipeEditPolicy.supportsEditFormat(version: nil))
        XCTAssertTrue(RecipeEditPolicy.canEdit(version: "3"))
        XCTAssertFalse(RecipeEditPolicy.canEdit(version: "1"))
        XCTAssertFalse(RecipeEditPolicy.canEdit(version: "2"))
    }

    func testIngredientAmountLikeBasqueCheesecake() {
        let sugar = IngredientData(
            id: "1",
            name: "Сахар",
            originalAmount: "350",
            unit: "г",
            order: 1
        )
        XCTAssertEqual(sugar.quantityText, "350")
        XCTAssertEqual(sugar.scaledDisplay(targetServings: 8, baseServings: 4), "700")

        let header = IngredientData(
            id: "h",
            name: "Начинка",
            hasQuantity: false
        )
        XCTAssertTrue(header.isHeaderRow)
        XCTAssertEqual(header.scaledDisplay(targetServings: 4, baseServings: 4), "")
    }

    func testIngredientEditListEstimatedHeightIsPositiveForTypicalRecipe() {
        let rows: [(number: Int?, ingredient: IngredientData)] = (1 ... 6).map { index in
            (
                index,
                IngredientData(
                    id: "ing-\(index)",
                    name: "Ingredient \(index)",
                    originalAmount: "\(index * 100)",
                    order: index
                )
            )
        }
        let editHeight = IngredientEditList.estimatedContentHeight(
            rows: rows,
            nutritionEnabled: true,
            includesNewRow: false
        )
        XCTAssertGreaterThan(editHeight, RecipeRowLayoutMetrics.rowHeight * 6)

        let viewHeight = IngredientEditList.estimatedContentHeight(
            rows: rows,
            nutritionEnabled: true,
            includesNewRow: false
        )
        XCTAssertEqual(editHeight, viewHeight)
    }

    func testIngredientEditListMeasuredContentHeightRequiresAllRows() {
        let ids = ["a", "b", "c"]
        let partial = IngredientEditList.measuredContentHeight(rowIds: ids, heights: ["a": 44, "b": 50])
        XCTAssertEqual(partial, 0)

        let full = IngredientEditList.measuredContentHeight(
            rowIds: ids,
            heights: ["a": 44, "b": 50, "c": 60]
        )
        XCTAssertEqual(full, 44 + 50 + 60 + 2)
    }

    func testIngredientEditListResolvedContentHeightFillsMissingWithEstimate() {
        let rows: [(number: Int?, ingredient: IngredientData)] = (0..<3).map { index in
            (
                index + 1,
                IngredientData(
                    id: "ing-\(index)",
                    name: "Ingredient \(index)",
                    originalAmount: "\(index + 1)",
                    order: index
                )
            )
        }
        let estimateOne = IngredientEditList.estimatedRowHeight(
            ingredient: rows[2].ingredient,
            nutritionEnabled: false
        )
        let partial = IngredientEditList.resolvedContentHeight(
            rows: rows,
            heights: ["ing-0": 66.7, "ing-1": 45],
            nutritionEnabled: false
        )
        XCTAssertEqual(partial, 66.7 + 45 + estimateOne + 2, accuracy: 0.01)

        let full = IngredientEditList.resolvedContentHeight(
            rows: rows,
            heights: ["ing-0": 66.7, "ing-1": 45, "ing-2": 66.7],
            nutritionEnabled: false
        )
        XCTAssertEqual(full, 66.7 + 45 + 66.7 + 2, accuracy: 0.01)
    }

    func testRecipeTitleEmojiLeading() {
        XCTAssertEqual(RecipeTitleEmoji.leadingEmoji(in: "🍕 Pizza"), "🍕")
        XCTAssertEqual(RecipeTitleEmoji.leadingEmoji(in: "  🍕 Pizza"), "🍕")
        XCTAssertEqual(RecipeTitleEmoji.leadingEmoji(in: "👨‍👩‍👧 Family"), "👨‍👩‍👧")
        XCTAssertNil(RecipeTitleEmoji.leadingEmoji(in: "Cake 🍰"))
    }

    func testRecipeTitleEmojiDisplayName() {
        XCTAssertEqual(RecipeTitleEmoji.titleWithoutLeadingEmoji("🍕  Pizza"), "Pizza")
        XCTAssertEqual(RecipeTitleEmoji.titleWithoutLeadingEmoji("  🍕 Pizza"), "Pizza")
        XCTAssertEqual(RecipeTitleEmoji.titleWithoutLeadingEmoji("Cake 🍰"), "Cake 🍰")
        XCTAssertEqual(RecipeTitleEmoji.titleWithoutLeadingEmoji("🍕"), "")
    }

    func testRecipeCollectionMergeKeepsRecipeColorWhenSetEvenIfCollectionNewer() {
        let recipe = RecipeData(
            id: "r1",
            name: "Cake",
            servings: 4,
            color: "#B51A00",
            version: "3",
            description: nil,
            ingredients: [],
            nutrition: nil,
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "2026-06-01T10:00:00.000Z",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
        let entry = CollectionEntry(
            id: "r1",
            name: "Cake",
            color: "#3b82f6",
            imageUrl: nil,
            updatedAt: "2026-06-02T12:00:00.000Z",
            deleted: false,
            isPinned: false
        )
        let merged = RecipeCollectionMerge.merged(recipe, with: entry)
        XCTAssertEqual(merged.color, "#B51A00")
    }

    func testRecipeCollectionMergeUsesRecipeColorWhenRecipeNewer() {
        let recipe = RecipeData(
            id: "r1",
            name: "Cake",
            servings: 4,
            color: "#111111",
            version: "3",
            description: nil,
            ingredients: [],
            nutrition: nil,
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "2026-06-03T12:00:00.000Z",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
        let entry = CollectionEntry(
            id: "r1",
            name: "Cake",
            color: "#AABBCC",
            imageUrl: nil,
            updatedAt: "2026-06-01T10:00:00.000Z",
            deleted: false,
            isPinned: false
        )
        let merged = RecipeCollectionMerge.merged(recipe, with: entry)
        XCTAssertEqual(merged.color, "#111111")
    }

    func testRecipeCollectionMergeUsesCollectionWhenRecipeColorEmpty() {
        let recipe = RecipeData(
            id: "r1",
            name: "Cake",
            servings: 4,
            color: "   ",
            version: "3",
            description: nil,
            ingredients: [],
            nutrition: nil,
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
        let entry = CollectionEntry(
            id: "r1",
            name: "Cake",
            color: "oklch(0.7 0.2 120)",
            imageUrl: nil,
            updatedAt: "",
            deleted: false,
            isPinned: false
        )
        let merged = RecipeCollectionMerge.merged(recipe, with: entry)
        XCTAssertEqual(merged.color, "oklch(0.7 0.2 120)")
    }

    func testRecipeImageVersionToken() {
        XCTAssertEqual(
            RecipeImageVersion.token(from: "user/recipe-id/full/abc123.webp"),
            "abc123"
        )
        XCTAssertNil(RecipeImageVersion.token(from: nil))
        XCTAssertNil(RecipeImageVersion.token(from: ""))
    }

    func testXmlFragmentHTMLEscapes() {
        XCTAssertEqual(
            XmlFragmentToHTML.escapeHTML("a < b & \"c\""),
            "a &lt; b &amp; &quot;c&quot;"
        )
    }

    func testXmlFragmentConvertsParagraph() {
        let xml = "<paragraph>Mix flour</paragraph><paragraph>Bake</paragraph>"
        let html = XmlFragmentToHTML.html(fromSerializedXML: xml, ingredients: [])
        XCTAssertEqual(html, "<p>Mix flour</p><p>Bake</p>")
    }

    /// Tiptap stores bold as Y.XmlText delta marks (`attributes.bold`), not only as <bold> elements.
    func testXmlFragmentPreservesInlineBoldMarksFromYjsState() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/recipe-adjaruli-yjs.bin")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("Fixture missing at \(fixtureURL.path)")
        }

        let state = try Data(contentsOf: fixtureURL)
        let recipe = await RecipeReader.parse(state: state, recipeId: "fixture")
        let html = recipe?.description ?? ""

        XCTAssertTrue(html.contains("<h1>"), "Expected heading block in \(html)")
        XCTAssertTrue(html.contains("<strong>ри му</strong>"), "Expected inline bold in heading: \(html)")
        XCTAssertTrue(html.contains("<strong>Пеки аджарули</strong>"), "Expected bold paragraph: \(html)")

        let document = RecipeDescriptionParser.parse(html)
        XCTAssertTrue(document.blocks.contains { block in
            guard case .heading(_, let level, let runs) = block else { return false }
            return level == 1 && runs.contains { if case .strong("ри му") = $0 { return true }; return false }
        })
        XCTAssertTrue(document.blocks.contains { block in
            guard case .paragraph(_, let runs) = block else { return false }
            return runs.contains { if case .strong("Пеки аджарули") = $0 { return true }; return false }
        })
    }

    /// Pure parser test: `<h1>Бе<strong>ри му</strong>ку</h1>` → `.heading(level:1)` + `.strong("ри му")`.
    func testDescriptionParserHeadingWithInlineBold() {
        let html = "<h1>Бе<strong>ри му</strong>ку</h1>"
        let doc = RecipeDescriptionParser.parse(html)
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .heading(_, let level, let runs) = doc.blocks.first else {
            XCTFail("Expected heading block, got \(doc.blocks)")
            return
        }
        XCTAssertEqual(level, 1)
        XCTAssertTrue(runs.contains(.plain("Бе")), "Expected plain 'Бе' in \(runs)")
        XCTAssertTrue(runs.contains(.strong("ри му")), "Expected strong 'ри му' in \(runs)")
        XCTAssertTrue(runs.contains(.plain("ку")), "Expected plain 'ку' in \(runs)")
    }

    func testDescriptionFixtureParsesAllElements() {
        let doc = RecipeDescriptionParser.parse(RecipeDescriptionFixture.allElementsHTML)
        let ordered = doc.blocks.filter {
            if case .orderedStep = $0 { return true }
            return false
        }
        XCTAssertEqual(ordered.count, 3)
        XCTAssertTrue(doc.blocks.contains { block in
            if case .paragraph(_, let runs) = block {
                return runs.contains { if case .link = $0 { return true }; return false }
            }
            return false
        })
        XCTAssertTrue(doc.blocks.contains { block in
            if case .orderedStep(_, _, let runs) = block {
                return runs.contains { run in
                    if case .timer(let ref) = run {
                        return ref.durationSeconds == 1800 && ref.resolvedName == "Bake"
                    }
                    return false
                }
            }
            return false
        })
        XCTAssertTrue(doc.blocks.contains { block in
            if case .orderedStep(_, _, let runs) = block {
                return runs.contains { if case .ingredient = $0 { return true }; return false }
            }
            return false
        })
    }

    func testTimerReferenceLinkRoundTrip() throws {
        let ref = RecipeDescriptionTimerReference(
            displayText: "30 minutes",
            durationSeconds: 1800,
            type: .minutes,
            name: "Bake"
        )
        let url = try XCTUnwrap(ref.linkURL())
        let parsed = try XCTUnwrap(RecipeDescriptionTimerReference.from(link: url))
        XCTAssertEqual(parsed, ref)
    }

    func testTimerReferenceMenuSubtitleMatchesWebDropdown() {
        let named = RecipeDescriptionTimerReference(
            displayText: "60 minutes",
            durationSeconds: 3600,
            type: .minutes,
            name: "Выпекаем"
        )
        XCTAssertEqual(named.menuSubtitle, "Выпекаем, 60 minutes")

        let unnamed = RecipeDescriptionTimerReference(
            displayText: "30 minutes",
            durationSeconds: 1800,
            type: .minutes,
            name: nil
        )
        XCTAssertEqual(unnamed.menuSubtitle, "30 minutes")
    }

    func testTimerUtilsRemainingAndFormat() {
        let timer = RecipeTimer(
            id: "t1",
            name: "Bake",
            duration: 3600,
            type: .minutes,
            isRunning: true,
            isPaused: false
        )
        // Anchor endTime on a whole-second boundary so `floor(...)` is deterministic
        // (test was flaky when endTime = Date() + 125.x due to subsecond flooring).
        let endTime = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate).rounded() + 125)
        timer.endTime = endTime
        XCTAssertEqual(TimerUtils.remainingSeconds(for: timer, now: endTime.addingTimeInterval(-125)), 125)
        XCTAssertEqual(TimerUtils.formatTime(seconds: 125), "02:05")
        XCTAssertEqual(TimerUtils.formatTime(seconds: -5), "-00:05")
    }

    func testXmlFragmentHTMLIncludesLinkAndTimerSpans() {
        let xml = """
        <paragraph>See <link href="https://example.com">Example</link></paragraph>
        <paragraph><timer data-duration="600" data-type="minutes" data-value="10">10 minutes</timer></paragraph>
        """
        let html = XmlFragmentToHTML.html(fromSerializedXML: xml, ingredients: []) ?? ""
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
        XCTAssertTrue(html.contains("timer-reference"))
        XCTAssertTrue(html.contains("10 minutes"))
    }

    func testDescriptionParserFindsAnchorLinks() {
        let html = #"<p>Visit <a href="https://recipe-scaler.ru/mcp">recipe-scaler.ru/mcp</a> today.</p>"#
        let doc = RecipeDescriptionParser.parse(html)
        let hasLink = doc.blocks.contains { block in
            guard case .paragraph(_, let runs) = block else { return false }
            return runs.contains { if case .link(let url, _) = $0 { return url.contains("recipe-scaler.ru") }; return false }
        }
        XCTAssertTrue(hasLink)
    }

    func testPrefetchPreviewsRemovesCacheWhenImageUrlEmpty() async {
        let recipeId = "recipe-no-image"
        // Disk cache lives under Application Support (migrated away from Caches in spec 003).
        let previewURL = RecipeImageDiskCache.fileURL(recipeId: recipeId, variant: .preview)

        try? FileManager.default.createDirectory(
            at: previewURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data([0xFF]).write(to: previewURL)

        let entry = CollectionEntry(
            id: recipeId,
            name: "Test",
            color: "oklch(0.65 0.25 270)",
            imageUrl: nil,
            updatedAt: "",
            deleted: false,
            isPinned: false
        )

        await RecipeImageService.shared.prefetchPreviews(entries: [entry], allowNetwork: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: previewURL.path))
        let cached = await RecipeImageService.shared.localFileURL(recipeId: recipeId, variant: .preview)
        XCTAssertNil(cached)
    }

    func testRecipeCachedImageLoadTaskIdentityExcludesNetworkFlag() {
        let offlineKey = RecipeCachedImageView.loadTaskIdentity(
            recipeId: "r1",
            imageUrl: "https://example.com/v1",
            variant: .preview
        )
        let onlineKey = RecipeCachedImageView.loadTaskIdentity(
            recipeId: "r1",
            imageUrl: "https://example.com/v1",
            variant: .preview
        )
        XCTAssertEqual(offlineKey, onlineKey)
        XCTAssertEqual(offlineKey, "r1|https://example.com/v1|preview")

        let otherVariant = RecipeCachedImageView.loadTaskIdentity(
            recipeId: "r1",
            imageUrl: "https://example.com/v1",
            variant: .full
        )
        XCTAssertNotEqual(offlineKey, otherVariant)

        let otherUrl = RecipeCachedImageView.loadTaskIdentity(
            recipeId: "r1",
            imageUrl: "https://example.com/v2",
            variant: .preview
        )
        XCTAssertNotEqual(offlineKey, otherUrl)
    }

    func testPublicCachedImageLoadTaskIdentityExcludesNetworkFlag() {
        let url = URL(string: "https://example.com/photo.jpg")!
        let offlineKey = PublicCachedImageView.loadTaskIdentity(
            url: url,
            maxPixelSize: 800,
            fullWidthHero: false
        )
        let onlineKey = PublicCachedImageView.loadTaskIdentity(
            url: url,
            maxPixelSize: 800,
            fullWidthHero: false
        )
        XCTAssertEqual(offlineKey, onlineKey)
        XCTAssertEqual(offlineKey, "https://example.com/photo.jpg|800|false")

        let heroKey = PublicCachedImageView.loadTaskIdentity(
            url: url,
            maxPixelSize: 800,
            fullWidthHero: true
        )
        XCTAssertNotEqual(offlineKey, heroKey)
    }

    func testRecipeImageDiskCacheDetectsExistingFile() throws {
        let recipeId = "verify-disk-cache"
        let fileURL = RecipeImageDiskCache.fileURL(recipeId: recipeId, variant: .full)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertNil(RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .full))
        try Data([0x00]).write(to: fileURL)
        XCTAssertEqual(
            RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .full),
            fileURL
        )
    }

    func testRecipeImageDiskCacheUsesApplicationSupport() {
        let url = RecipeImageDiskCache.fileURL(recipeId: "path-check", variant: .preview)
        XCTAssertTrue(url.path.contains("Application Support"))
        XCTAssertFalse(url.path.contains("/Caches/"))
    }

    func testRecipeImageMigrationFromCaches() throws {
        let migrationKey = "recipeImage.diskCache.migratedToApplicationSupport"
        let hadMigrated = UserDefaults.standard.bool(forKey: migrationKey)
        defer {
            UserDefaults.standard.set(hadMigrated, forKey: migrationKey)
            try? FileManager.default.removeItem(at: RecipeImageDiskCache.legacyCachesDirectoryURL)
            try? FileManager.default.removeItem(at: RecipeImageDiskCache.baseDirectoryURL)
        }
        UserDefaults.standard.set(false, forKey: migrationKey)

        let legacyDir = RecipeImageDiskCache.legacyCachesDirectoryURL
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyFile = legacyDir.appendingPathComponent("migrate-test_full.webp")
        try Data([0x01]).write(to: legacyFile)

        // Migration is lazy: it only runs when `migrateFromCachesIfNeeded()` is invoked
        // (called from AppContainer bootstrap in production). Trigger it explicitly here.
        RecipeImageDiskCache.migrateFromCachesIfNeeded()

        XCTAssertNotNil(RecipeImageDiskCache.existingFileURL(recipeId: "migrate-test", variant: .full))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyFile.path))
    }

    func testPublicImageDiskCacheDetectsExistingFile() throws {
        let url = URL(string: "https://example.com/api/discover/recipes/test/image")!
        let fileURL = PublicImageDiskCache.fileURL(for: url)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertNil(PublicImageDiskCache.existingFileURL(for: url))
        try Data([0x00]).write(to: fileURL)
        XCTAssertEqual(PublicImageDiskCache.existingFileURL(for: url), fileURL)
    }

    func testPublicImageCacheServiceStoresAndRevalidates304() async throws {
        let testHost = "public-image-cache-test.local"
        let url = URL(string: "https://\(testHost)/image.webp")!
        let key = PublicImageDiskCache.cacheKey(for: url)
        let etagKey = "publicImage.\(key).etag"
        let storedEtag = UserDefaults.standard.string(forKey: etagKey)
        defer {
            if let storedEtag {
                UserDefaults.standard.set(storedEtag, forKey: etagKey)
            } else {
                UserDefaults.standard.removeObject(forKey: etagKey)
            }
            try? FileManager.default.removeItem(at: PublicImageDiskCache.baseDirectoryURL)
            PublicImageCacheTestURLProtocol.reset()
            URLProtocol.unregisterClass(PublicImageCacheTestURLProtocol.self)
        }

        PublicImageCacheTestURLProtocol.reset()
        URLProtocol.registerClass(PublicImageCacheTestURLProtocol.self)

        let payload = Data([0x52, 0x49, 0x46, 0x46])
        PublicImageCacheTestURLProtocol.handler = { request in
            let count = PublicImageCacheTestURLProtocol.incrementCallCount()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: count == 1 ? 200 : 304,
                httpVersion: nil,
                headerFields: ["ETag": "\"v1\""]
            )!
            return (response, count == 1 ? payload : Data())
        }

        let first = try await PublicImageCacheService.shared.fetchAndCache(url: url)
        XCTAssertEqual(first.statusCode, 200)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.localURL.path))

        let second = try await PublicImageCacheService.shared.fetchAndCache(url: url)
        XCTAssertEqual(second.statusCode, 304)
        XCTAssertEqual(
            try Data(contentsOf: second.localURL),
            payload
        )
        XCTAssertEqual(PublicImageCacheTestURLProtocol.callCount, 2)
    }

    func testRecipeImageDecoderDownsamplesLargeFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-decode-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200))
        let large = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        }
        try XCTUnwrap(large.pngData()).write(to: fileURL)

        let decoded = RecipeImageDecoder.decode(
            fileURL: fileURL,
            maxPixelSize: RecipeImageDecoder.fullMaxPixelSize
        )
        let image = try XCTUnwrap(decoded)
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), CGFloat(RecipeImageDecoder.fullMaxPixelSize) + 1)
    }

    func testRecipeImageDisplayCacheReturnsSameInstance() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-mem-cache-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let img = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        try XCTUnwrap(img.pngData()).write(to: fileURL)

        let first = try XCTUnwrap(RecipeImageDisplayCache.image(fileURL: fileURL, variant: .full))
        let second = try XCTUnwrap(RecipeImageDisplayCache.image(fileURL: fileURL, variant: .full))
        XCTAssertTrue(first === second)
    }

    func testRecipeTitleEmojiSortOrder() {
        let input = ["🍕 Pizza", "Apple Pie", "☕ Coffee"]
        let sorted = input.sorted { lhs, rhs in
            RecipeTitleEmoji.compareNames(lhs, rhs) == .orderedAscending
        }
        XCTAssertEqual(sorted, ["Apple Pie", "☕ Coffee", "🍕 Pizza"])
    }

    func testRapidIngredientUpdatesDoNotCrash() async throws {
        let userId = "user-rapid"
        let ingredientId = "ing-rapid"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Rapid")
        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Flour")),
                    ("amount", .string("200")),
                    ("order", .int(1)),
                ]),
            ]), txn: txn)
        }

        for index in 0..<50 {
            let ingredient = IngredientData(
                id: ingredientId,
                name: "Name \(index)",
                amount: "200",
                originalAmount: "200",
                unit: "",
                order: 1
            )
            try await manager.updateIngredient(recipeId: recipeId, ingredient: ingredient)
            _ = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        }
    }

    func testLocalUpdateEmittedAfterIngredientRename() async throws {
        let userId = "user-local-sync"
        let ingredientId = "ing-1"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        // Holder captures the latest delivery. `persistAndDeliver` schedules the
        // handler on a detached Task, so the test must poll for its effect rather
        // than assume synchronous delivery.
        let holder = SyncUpdateHolder()
        await manager.setLocalUpdateHandler { context, update in
            holder.record(recipeId: context.recipeId ?? "", update: update)
        }

        let recipeId = try await manager.createRecipe(name: "Local sync")

        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Flour")),
                    ("amount", .string("200")),
                    ("order", .int(1)),
                ]),
            ]), txn: txn)
        }

        let renamed = IngredientData(
            id: ingredientId,
            name: "Whole wheat flour",
            amount: "200",
            originalAmount: "200",
            unit: "",
            order: 1
        )
        try await manager.updateIngredient(recipeId: recipeId, ingredient: renamed)

        // Wait for the update-ingredient delivery (creates a update with the new
        // ingredient name). We poll rather than await a single continuation
        // because `createRecipe` also schedules a delivery through the same
        // handler, and resuming the same continuation twice is undefined.
        let update = try await waitForSyncUpdate(holder: holder, recipeId: recipeId)

        XCTAssertEqual(update.recipeId, recipeId)
        XCTAssertFalse(update.data.isEmpty)

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.ingredients.first?.name, "Whole wheat flour")
    }

    private func waitForSyncUpdate(
        holder: SyncUpdateHolder,
        recipeId: String,
        timeout: TimeInterval = 5
    ) async throws -> (recipeId: String, data: Data) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snap = holder.snapshot, snap.recipeId == recipeId, !snap.data.isEmpty {
                return snap
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "TestTimeout", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Timed out waiting for sync update for \(recipeId)",
        ])
    }

    private final class SyncUpdateHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedRecipeId: String?
        private var storedData: Data?

        func record(recipeId: String, update: Data) {
            lock.lock()
            storedRecipeId = recipeId
            storedData = update
            lock.unlock()
        }

        var snapshot: (recipeId: String, data: Data)? {
            lock.lock()
            defer { lock.unlock() }
            if let storedRecipeId, let storedData {
                return (storedRecipeId, storedData)
            }
            return nil
        }
    }

    func testUpdateIngredientRenameDoesNotCrash() async throws {
        let userId = "user-ingredient-rename"
        let ingredientId = "ing-1"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Rename test")
        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "ingredients", value: .yarray([
                .map([
                    ("id", .string(ingredientId)),
                    ("name", .string("Flour")),
                    ("amount", .string("200")),
                    ("order", .int(1)),
                ]),
            ]), txn: txn)
        }

        let renamed = IngredientData(
            id: ingredientId,
            name: "Whole wheat flour",
            amount: "200",
            originalAmount: "200",
            unit: "",
            order: 1
        )
        try await manager.updateIngredient(recipeId: recipeId, ingredient: renamed)

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.ingredients.first?.name, "Whole wheat flour")
    }

    func testUpdateRecipeColorThenSortCollectionDoesNotCrash() async throws {
        let userId = "user-color-sort"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "🍕 Pizza")
        let recipeDoc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await recipeDoc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "color", value: .string("oklch(0.65 0.25 270)"), txn: txn)
        }

        try await manager.updateRecipeColor(recipeId: recipeId, color: "#FF5500")

        let entries = try await manager.readCollectionEntries()
        let sorted = RecipeTitleEmoji.sortCollectionEntries(entries)
        XCTAssertEqual(sorted.first?.color, "#FF5500")
        XCTAssertEqual(RecipeTitleEmoji.leadingEmoji(in: sorted.first?.name), "🍕")
    }

    func testUpdateRecipeColorDoesNotCrash() async throws {
        let userId = "user-color"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Color test")

        try await manager.updateRecipeColor(recipeId: recipeId, color: "#AABBCC")

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.color, "#AABBCC")
    }

    func testUpdateNutritionDoesNotCrash() async throws {
        let userId = "user-nutrition"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Nutrition test")

        try await manager.updateNutrition(
            recipeId: recipeId,
            calories: 250,
            protein: 20,
            fat: 8,
            carbs: 30
        )

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.nutrition?.calories, 250)
        XCTAssertEqual(readBack?.nutrition?.protein, 20)
        XCTAssertEqual(readBack?.nutrition?.fat, 8)
        XCTAssertEqual(readBack?.nutrition?.carbs, 30)
    }

    /// Regression (072 review): `updateIngredient` / `removeIngredient` used to
    /// write only the root-level `nutritionOutdated`, which the nested-only
    /// `readNutrition` ignores — the «данные устарели» banner never appeared.
    /// Both writers must go through the dual-write `setNutritionOutdated`.
    func testUpdateAndRemoveIngredientMarkNutritionOutdated() async throws {
        let userId = "user-outdated-flag"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Outdated flag test")
        let ingredient = IngredientData(
            id: "ing-1",
            name: "Мука",
            amount: "200",
            originalAmount: "200",
            unit: "g",
            order: 1
        )
        try await manager.addIngredient(recipeId: recipeId, ingredient: ingredient)

        let updated = IngredientData(
            id: "ing-1",
            name: "Мука высшего сорта",
            amount: "200",
            originalAmount: "200",
            unit: "g",
            order: 1
        )
        try await manager.updateIngredient(recipeId: recipeId, ingredient: updated)
        var readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(
            readBack?.nutrition?.nutritionOutdated,
            true,
            "editing an ingredient must flag nutrition as outdated (nested write, which the reader honors)"
        )

        try await manager.removeIngredient(recipeId: recipeId, ingredientId: ingredient.id)
        readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(
            readBack?.nutrition?.nutritionOutdated,
            true,
            "removing an ingredient must keep the outdated flag set"
        )
    }

    func testAddIngredientViaIngredientMapDoesNotCrash() async throws {
        let userId = "user-add-ingredient"
        let recipeId = "recipe-add-ingredient"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        await doc.ensureRecipeCreateRoots()
        try await doc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "version", value: .string("v3"), txn: txn)
            map.insert(key: "ingredients", value: .yarray([]), txn: txn)
        }

        let ingredient = IngredientData(
            id: "ing-new",
            name: "Мука 🌾",
            amount: "200",
            originalAmount: "200",
            unit: "g",
            order: 1,
            calories: 364,
            protein: 10,
            fat: 1,
            carbs: 76
        )
        try await manager.addIngredient(recipeId: recipeId, ingredient: ingredient)

        let readBack = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(readBack?.ingredients.count, 1)
        XCTAssertEqual(readBack?.ingredients.first?.name, "Мука 🌾")
        XCTAssertEqual(readBack?.ingredients.first?.calories, 364)
    }

    /// #4 perf: `addIngredients` batched insert must produce identical doc state to per-item `addIngredient`.
    func testAddIngredientsBatchedMatchesPerItemState() async throws {
        let userIdA = "user-batch-peritem"
        let userIdB = "user-batch-once"
        let recipeIdA = "recipe-a"
        let recipeIdB = "recipe-b"
        let storeA = try YDocStore.inMemory()
        let storeB = try YDocStore.inMemory()
        let managerA = DocumentManager(store: storeA)
        let managerB = DocumentManager(store: storeB)
        await managerA.setUserId(userIdA)
        await managerB.setUserId(userIdB)

        // Set up v3 docs using the same lightweight path as testAddIngredientViaIngredientMapDoesNotCrash
        for (manager, recipeId, userId) in [(managerA, recipeIdA, userIdA), (managerB, recipeIdB, userIdB)] as [(DocumentManager, String, String)] {
            let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
            await doc.ensureRecipeCreateRoots()
            try await doc.testWriteTransaction { _, txn in
                guard let mapBranch = ytype_get(txn, "recipe") else { return }
                let map = YrsMap(branch: mapBranch)
                map.insert(key: "version", value: .string("v3"), txn: txn)
                map.insert(key: "ingredients", value: .yarray([]), txn: txn)
            }
        }

        let ingredients: [IngredientData] = (1...5).map { i in
            IngredientData(
                id: "ing-\(i)",
                name: "Ingredient \(i)",
                amount: "\(i * 100)",
                originalAmount: "\(i * 100)",
                unit: "g",
                order: i,
                calories: Double(i * 10),
                protein: Double(i),
                fat: Double(i),
                carbs: Double(i * 2)
            )
        }

        for ing in ingredients {
            try await managerA.addIngredient(recipeId: recipeIdA, ingredient: ing)
        }
        try await managerB.addIngredients(recipeId: recipeIdB, ingredients: ingredients)

        let readA = try await managerA.readRecipeData(recipeId: recipeIdA, userId: userIdA)
        let readB = try await managerB.readRecipeData(recipeId: recipeIdB, userId: userIdB)

        XCTAssertEqual(readB?.ingredients.count, ingredients.count)
        XCTAssertEqual(readA?.ingredients.count, readB?.ingredients.count)

        let ordersA = readA?.ingredients.map(\.order)
        let ordersB = readB?.ingredients.map(\.order)
        XCTAssertEqual(ordersA, [1, 2, 3, 4, 5])
        XCTAssertEqual(ordersB, [1, 2, 3, 4, 5])

        for (a, b) in zip(readA?.ingredients ?? [], readB?.ingredients ?? []) {
            XCTAssertEqual(a.name, b.name)
            XCTAssertEqual(a.originalAmount, b.originalAmount)
            XCTAssertEqual(a.unit, b.unit)
            XCTAssertEqual(a.calories, b.calories)
            XCTAssertEqual(a.protein, b.protein)
            XCTAssertEqual(a.fat, b.fat)
            XCTAssertEqual(a.carbs, b.carbs)
        }
    }

    func testIngredientNutritionAggregation() {
        let a = IngredientData(
            id: "1",
            name: "Sugar",
            calories: 100,
            protein: 0,
            fat: 0,
            carbs: 25
        )
        let b = IngredientData(
            id: "2",
            name: "Butter",
            calories: 200,
            protein: 1,
            fat: 22,
            carbs: 0
        )
        let totals = IngredientData.aggregatedMacros(from: [a, b])
        XCTAssertEqual(totals?.calories, 300)
        XCTAssertEqual(totals?.protein, 1)
        XCTAssertEqual(totals?.fat, 22)
        XCTAssertEqual(totals?.carbs, 25)
    }

    func testRecipeNutritionDisplayPerServingMatchesWeb() {
        let recipe = RecipeData(
            id: "r1",
            name: "Test",
            servings: 3,
            color: "oklch(0.65 0.25 270)",
            version: "3",
            description: nil,
            ingredients: [
                IngredientData(id: "1", name: "A", calories: 300, protein: 10, fat: 5, carbs: 20),
                IngredientData(id: "2", name: "B", calories: 150, protein: 5, fat: 2, carbs: 10),
            ],
            nutrition: NutritionData(calories: 9999, protein: 0, fat: 0, carbs: 0, nutritionOutdated: false, extra: [:]),
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
        let effective = RecipeNutritionDisplay.effectiveMacros(from: recipe)
        XCTAssertEqual(effective?.calories, 450)

        let perServing = RecipeNutritionDisplay.displayMacros(
            effective: effective!,
            baseServings: 3,
            viewServings: 3,
            recipeServings: 3,
            totalWeight: nil,
            mode: .perServing
        )
        XCTAssertEqual(perServing.calories, 150)
    }

    func testRecipeServingsNormalizeStringAndScaled() {
        XCTAssertEqual(RecipeServings.normalize("10"), 10)
        XCTAssertEqual(RecipeServings.normalize("10,5"), 11)
        XCTAssertEqual(RecipeServings.normalize("0"), nil)
        XCTAssertEqual(RecipeServings.scaledServings(base: 1, scaleFactor: 10), 10)
        XCTAssertEqual(RecipeServings.scaledServings(base: 4, scaleFactor: 2.5), 10)
    }

    func testIngredientNutritionSummaryLineScaledMode() {
        let ingredient = IngredientData(
            id: "1",
            name: "Sugar",
            originalAmount: "200",
            unit: "г",
            calories: 800,
            protein: 8,
            fat: 0,
            carbs: 200,
            weight: 200
        )
        let line = IngredientNutritionDisplay.summaryLine(
            ingredient: ingredient,
            baseServings: 4,
            viewServings: 8,
            mode: .scaled
        )
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("1600") == true)
    }

    func testIngredientNutritionEditingPer100gRoundTrip() {
        let ingredient = IngredientData(
            id: "1",
            name: "Sugar",
            originalAmount: "200",
            unit: "г",
            calories: 800,
            protein: 0,
            fat: 0,
            carbs: 200,
            weight: 200
        )
        let per100g = IngredientNutritionEditing.per100gValues(from: ingredient)
        XCTAssertEqual(per100g.calories, 400)

        let absolute = IngredientNutritionEditing.absoluteValues(
            per100g: IngredientNutritionEditing.Per100gValues(calories: 400, protein: 0, fat: 0, carbs: 100),
            weightGrams: ingredient.resolvedWeightGrams
        )
        XCTAssertEqual(absolute.calories, 800)
        XCTAssertEqual(absolute.carbs, 200)
    }

    // MARK: - Collection pin & tombstone (was: libyrs test-host deadlock)
    //
    // History: this test and the _DISABLED_ sibling were `XCTSkip`'d because the
    // original body called `yarray(rawDoc, "recipes")` inside an active write
    // transaction. `yarray(YDoc*, const char*)` get-or-creates its own internal
    // write transaction in yrs C FFI, so calling it from inside another active
    // transaction on the same `YDoc` deadlocks on `event_listener::Listener::wait`
    // (`_pthread_cond_wait`) forever. Production code was fixed in commit 4c2516e
    // (MIK-155) by pre-creating the roots in `DocumentManager.getOrCreateDoc` →
    // `YrsDocument.ensureCollectionRoots()` and using `ytype_get(txn, ...)` instead.
    // The test body below mirrors that pattern: `getOrCreateDoc(key: ":collection")`
    // pre-creates the `recipes` array, then we read it inside the write txn via
    // `ytype_get`. No deadlock, no skip.
    func testCollectionPinAndTombstone() async throws {
        let userId = "user-col-mut"
        let recipeId = "recipe-col-mut"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let collectionDoc = try await manager.getOrCreateDoc(key: "\(userId):collection")
        try await collectionDoc.testWriteTransaction { _, txn in
            guard let arrayBranch = ytype_get(txn, RecipeFolderConstants.recipesArrayKey) else {
                XCTFail("recipes array root was not pre-created by ensureCollectionRoots()")
                return
            }
            let array = YrsArray(branch: arrayBranch)
            array.insert(
                value: .map([
                    ("id", .string(recipeId)),
                    ("name", .string("Soup")),
                    ("color", .string("#3b82f6")),
                    ("updatedAt", .string("2026-06-01T10:00:00Z")),
                    ("deleted", .bool(false)),
                    ("isPinned", .bool(false)),
                ]),
                at: 0,
                txn: txn
            )
        }

        try await manager.setCollectionEntryPinned(recipeId: recipeId, isPinned: true)
        var entries = try await manager.readCollectionEntries()
        XCTAssertTrue(entries.first { $0.id == recipeId }?.isPinned == true)

        try await manager.tombstoneCollectionEntry(recipeId: recipeId)
        entries = try await manager.readCollectionEntries()
        XCTAssertTrue(entries.first { $0.id == recipeId }?.deleted == true)
    }

    func testCreateRecipeWritesV3DocAndCollectionEntry() async throws {
        let userId = "user-create"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Fresh pasta")
        XCTAssertEqual(recipeId, recipeId.lowercased(), "recipe ids must be lowercase (web parity)")

        let entries = try await manager.readCollectionEntries()
        let entry = try XCTUnwrap(entries.first { $0.id == recipeId })
        XCTAssertEqual(entry.name, "Fresh pasta")
        XCTAssertFalse(entry.deleted)

        let recipe = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(recipe?.version, "v3")
        XCTAssertEqual(recipe?.servings, 1)
        XCTAssertEqual(recipe?.ingredients.count, 0)
    }

    func testUpdateRecipeServingsPersistsAsJSONNumber() async throws {
        let userId = "user-servings"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Scale me")
        try await manager.updateRecipeServings(recipeId: recipeId, servings: 20)

        let recipe = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(recipe?.servings, 20)

        try await manager.updateRecipeServings(recipeId: recipeId, servings: 10)
        let updated = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(updated?.servings, 10)
    }

    func testLegacyIntServingsStillReadable() async throws {
        let userId = "user-legacy-servings"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Legacy")
        let doc = try await manager.getOrCreateDoc(key: "\(userId):recipe:\(recipeId)")
        try await doc.testWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else {
                XCTFail("missing recipe map")
                return
            }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "servings", value: .int(20), txn: txn)
        }

        let recipe = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(recipe?.servings, 20)
    }

    func testUpdateRecipeNamePersistsInDocAndCollection() async throws {
        let userId = "user-title-save"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Before rename")
        try await manager.updateRecipeName(recipeId: recipeId, name: "After rename")

        let recipe = try await manager.readRecipeData(recipeId: recipeId, userId: userId)
        XCTAssertEqual(recipe?.name, "After rename")

        let entries = try await manager.readCollectionEntries()
        let entry = try XCTUnwrap(entries.first { $0.id == recipeId })
        XCTAssertEqual(entry.name, "After rename")

        let snapshot = try await store.loadSnapshot(docKey: "\(userId):recipe:\(recipeId)")
        XCTAssertNotNil(snapshot)
        XCTAssertFalse(snapshot?.state.isEmpty ?? true)
    }

    func testAppTabBarSymbolsExistInUIKit() {
        for tab in AppTab.allCases {
            XCTAssertNotNil(
                UIImage(systemName: tab.tabBarSymbol),
                "Missing SF Symbol for tab \(tab.rawValue): \(tab.tabBarSymbol)"
            )
        }
        XCTAssertNotNil(UIImage(systemName: "globe"))
        XCTAssertNotNil(
            UIImage(systemName: "sun.max"),
            "Missing SF Symbol for keep-awake toolbar: sun.max"
        )
        // Sanity check: a deliberately-invalid symbol name must yield `nil`.
        // We use this to ensure `UIImage(systemName:)` actually fails for unknown symbols.
        XCTAssertNil(
            UIImage(systemName: "this.is.not.a.real.sf.symbol.name"),
            "UIImage(systemName:) returned non-nil for an obviously-invalid name — SF Symbol set or SDK changed"
        )
    }

    func testShoppingListManualAddPersistsInSnapshot() async throws {
        let userId = "user-shopping"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        try await manager.addManualShoppingItem(label: "Milk")
        let snapshot = try await manager.readShoppingListSnapshot()
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.label, "Milk")
        XCTAssertNil(snapshot.items.first?.recipeId)
    }

    func testShoppingListIllustrationIdRoundTrip() async throws {
        let userId = "user-shopping-ill"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let item = ShoppingListItem(
            label: "200 g · Flour",
            recipeId: "recipe-1",
            ingredientId: "ing-1",
            recipeName: "Bread",
            illustrationId: "flour"
        )
        try await manager.addShoppingItems([item])
        let snapshot = try await manager.readShoppingListSnapshot()
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.illustrationId, "flour")
    }

    func testShoppingListFromRecipeCopiesIllustrationId() {
        let ingredient = IngredientData(
            id: "ing-tomato",
            name: "Помидоры",
            originalAmount: "2",
            unit: "шт",
            order: 1,
            illustrationId: "tomato"
        )
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: "recipe-1",
            recipeName: "Salad",
            ingredients: [ingredient]
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.illustrationId, "tomato")
    }

    func testShoppingListFromRecipeEligibilityMatchesWeb() {
        let eligible = IngredientData(
            id: "1",
            name: "Sugar",
            originalAmount: "100",
            unit: "g",
            order: 1
        )
        XCTAssertTrue(ShoppingListFromRecipe.isIngredientEligible(eligible))

        let header = IngredientData(id: "h", name: "Section", hasQuantity: false)
        XCTAssertFalse(ShoppingListFromRecipe.isIngredientEligible(header))
    }

    // MARK: - Recipe collections folders (026)

    func testCollectionVirtualFoldersDetectsKnownIds() {
        XCTAssertTrue(CollectionVirtualFolders.isKnownVirtualFolderId("all"))
        XCTAssertTrue(CollectionVirtualFolders.isKnownVirtualFolderId("uncategorized"))
        XCTAssertFalse(CollectionVirtualFolders.isKnownVirtualFolderId("user-folder-1"))
        XCTAssertFalse(CollectionVirtualFolders.isKnownVirtualFolderId(""))
    }

    func testRecipeFolderSortedActiveFiltersDeletedAndOrdersByName() {
        let folders = [
            RecipeFolder(id: "z", name: "Zeta", color: "oklch(0.65 0.25 270)", createdAt: "", updatedAt: "", deleted: false),
            RecipeFolder(id: "a", name: "Apple", color: "oklch(0.65 0.25 270)", createdAt: "", updatedAt: "", deleted: false),
            RecipeFolder(id: "g", name: "Ghost", color: "oklch(0.65 0.25 270)", createdAt: "", updatedAt: "", deleted: true),
            RecipeFolder(id: "m", name: "Middle", color: "oklch(0.65 0.25 270)", createdAt: "", updatedAt: "", deleted: false),
        ]
        let sorted = RecipeFolder.sortedActive(folders)
        XCTAssertEqual(sorted.map(\.id), ["a", "m", "z"])
    }

    func testRecipeFolderSortedActiveIgnoresLeadingEmojiAndIsCaseInsensitive() {
        let folders = [
            RecipeFolder(id: "1", name: "🍕 Pizza", color: "oklch(0.65 0.25 270)", createdAt: "", updatedAt: "", deleted: false),
            RecipeFolder(id: "2", name: "apple", color: "oklch(0.65 0.25 270)", createdAt: "", updatedAt: "", deleted: false),
            RecipeFolder(id: "3", name: "Banana", color: "oklch(0.65 0.25 270)", createdAt: "", updatedAt: "", deleted: false),
        ]
        let sorted = RecipeFolder.sortedActive(folders)
        XCTAssertEqual(sorted.map(\.id), ["2", "3", "1"])
    }

    func testCollectionRecipesIndexBuildGroupsByFolderAndCounts() {
        let entries = [
            CollectionEntry(id: "r1", name: "A", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: false, folderIds: ["f1"]),
            CollectionEntry(id: "r2", name: "B", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: false, folderIds: ["f1", "f2"]),
            CollectionEntry(id: "r3", name: "C", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: false, folderIds: []),
            CollectionEntry(id: "r4", name: "D", color: "#000", imageUrl: nil, updatedAt: "", deleted: true, isPinned: false, folderIds: ["f1"]),
        ]
        let index = CollectionRecipesIndexBuilder.build(from: entries)
        XCTAssertEqual(index.live.map(\.id), ["r1", "r2", "r3"])
        XCTAssertEqual(index.uncategorized.map(\.id), ["r3"])
        XCTAssertEqual(index.countByFolder["f1"], 2)
        XCTAssertEqual(index.countByFolder["f2"], 1)
        XCTAssertNil(index.countByFolder["fX"])
        XCTAssertEqual(index.folderRecipesById["f1"]?.map(\.id), ["r1", "r2"])
        XCTAssertEqual(index.folderRecipesById["f2"]?.map(\.id), ["r2"])
    }

    func testCollectionRecipesIndexPinnedFirstThenByName() {
        let entries = [
            CollectionEntry(id: "z", name: "Zeta", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: false, folderIds: []),
            CollectionEntry(id: "p", name: "Pinned", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: true, folderIds: []),
            CollectionEntry(id: "a", name: "Apple", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: false, folderIds: []),
        ]
        let index = CollectionRecipesIndexBuilder.build(from: entries)
        XCTAssertEqual(index.live.map(\.id), ["p", "a", "z"])
        XCTAssertEqual(index.pinned.map(\.id), ["p"])
        XCTAssertEqual(index.unpinned.map(\.id), ["a", "z"])
    }

    func testCollectionRecipesIndexPartitionPinned() {
        let sorted: [CollectionEntry] = [
            CollectionEntry(id: "p1", name: "P1", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: true, folderIds: []),
            CollectionEntry(id: "p2", name: "P2", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: true, folderIds: []),
            CollectionEntry(id: "u1", name: "U1", color: "#000", imageUrl: nil, updatedAt: "", deleted: false, isPinned: false, folderIds: []),
        ]
        let parts = CollectionRecipesIndex.partitionPinned(sorted)
        XCTAssertEqual(parts.pinned.map(\.id), ["p1", "p2"])
        XCTAssertEqual(parts.unpinned.map(\.id), ["u1"])
        XCTAssertEqual(CollectionRecipesIndex.partitionPinned([]).pinned.count, 0)
        XCTAssertEqual(CollectionRecipesIndex.empty.pinned.count, 0)
    }

    func testFolderDisplayNameReturnsLocalizedNoTitleForBlankNames() {
        // Sentinel + whitespace storage both resolve to a non-empty localized title.
        XCTAssertFalse(FolderDisplayName.displayName(forStoredName: "").isEmpty)
        XCTAssertFalse(FolderDisplayName.displayName(forStoredName: "   ").isEmpty)
        XCTAssertEqual(FolderDisplayName.displayName(forStoredName: "Desserts"), "Desserts")
        XCTAssertEqual(FolderDisplayName.displayName(forStoredName: "  Spices  "), "Spices")
    }

    func testFolderDisplayPresentationSeparatesLeadingEmojiAndCleansLabel() {
        XCTAssertEqual(
            FolderDisplayName.presentation(forStoredName: "🍕 Pizza"),
            FolderDisplayNamePresentation(leadingEmoji: "🍕", displayName: "Pizza")
        )
        XCTAssertEqual(
            FolderDisplayName.presentation(forStoredName: "  👨‍👩‍👧 Family"),
            FolderDisplayNamePresentation(leadingEmoji: "👨‍👩‍👧", displayName: "Family")
        )
    }

    func testFolderDisplayPresentationSupportsFlagsKeycapsAndEmojiOnlyNames() {
        XCTAssertEqual(
            FolderDisplayName.presentation(forStoredName: "🇺🇸 Road trips"),
            FolderDisplayNamePresentation(leadingEmoji: "🇺🇸", displayName: "Road trips")
        )
        XCTAssertEqual(
            FolderDisplayName.presentation(forStoredName: "1️⃣ Recipes"),
            FolderDisplayNamePresentation(leadingEmoji: "1️⃣", displayName: "Recipes")
        )
        XCTAssertEqual(
            FolderDisplayName.presentation(forStoredName: "Road 🍰 trips"),
            FolderDisplayNamePresentation(leadingEmoji: nil, displayName: "Road 🍰 trips")
        )
        XCTAssertEqual(
            FolderDisplayName.presentation(forStoredName: "🍕"),
            FolderDisplayNamePresentation(
                leadingEmoji: "🍕",
                displayName: String(localized: "recipes.no-title")
            )
        )
    }

    func testRecipeFolderRoutesShouldUseFolderRecipePathMatchesWeb() {
        let flat = RecipeFolderRoutes.ViewMode.flat
        let collections = RecipeFolderRoutes.ViewMode.collections

        XCTAssertFalse(RecipeFolderRoutes.shouldUseFolderRecipePath(
            activeFolderId: "f1", viewMode: flat, recipeFolderIds: ["f1"]
        ))
        XCTAssertFalse(RecipeFolderRoutes.shouldUseFolderRecipePath(
            activeFolderId: nil, viewMode: collections, recipeFolderIds: ["f1"]
        ))
        XCTAssertTrue(RecipeFolderRoutes.shouldUseFolderRecipePath(
            activeFolderId: "uncategorized", viewMode: collections, recipeFolderIds: []
        ))
        XCTAssertTrue(RecipeFolderRoutes.shouldUseFolderRecipePath(
            activeFolderId: "all", viewMode: collections, recipeFolderIds: ["f1"]
        ))
        XCTAssertFalse(RecipeFolderRoutes.shouldUseFolderRecipePath(
            activeFolderId: "all", viewMode: collections, recipeFolderIds: []
        ))
        XCTAssertTrue(RecipeFolderRoutes.shouldUseFolderRecipePath(
            activeFolderId: "f1", viewMode: collections, recipeFolderIds: ["f1", "f2"]
        ))
        XCTAssertFalse(RecipeFolderRoutes.shouldUseFolderRecipePath(
            activeFolderId: "f1", viewMode: collections, recipeFolderIds: ["f2"]
        ))
    }

    func testRecipeFolderRoutesIsValidFolderIdAcceptsVirtualAndUserIds() {
        XCTAssertTrue(RecipeFolderRoutes.isValidFolderId("all", userFolderIds: []))
        XCTAssertTrue(RecipeFolderRoutes.isValidFolderId("uncategorized", userFolderIds: []))
        XCTAssertTrue(RecipeFolderRoutes.isValidFolderId("f1", userFolderIds: ["f1"]))
        XCTAssertFalse(RecipeFolderRoutes.isValidFolderId("f1", userFolderIds: []))
    }

    func testCreateFolderWritesActiveFolderEntry() async throws {
        let userId = "user-folder-create"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let id = try await manager.createFolder(name: "Desserts")
        XCTAssertFalse(id.isEmpty)

        let folders = try await manager.readFolders()
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.name, "Desserts")
        XCTAssertFalse(folders.first?.deleted ?? true)
        XCTAssertEqual(folders.first?.color, RecipeFolderConstants.defaultFolderColor)
    }

    /// Legacy `document_loaded` / recovery may replace the collection doc without
    /// root `folders`/`recipes` arrays. Folder create from CollectionAssignSheet
    /// must still succeed after `replaceDocument`.
    func testCreateFolderAfterReplaceDocumentWithoutCollectionRoots() async throws {
        let userId = "user-folder-replace"
        let key = "\(userId):collection"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let legacyDoc = try YrsDocument()
        let encoded = await legacyDoc.encodeStateAsUpdate()
        let state = try XCTUnwrap(encoded)
        try await manager.replaceDocument(key: key, state: state)

        let id = try await manager.createFolder(name: "Assign sheet")
        XCTAssertFalse(id.isEmpty)
        let folders = try await manager.readFolders()
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.name, "Assign sheet")
    }

    func testCreateFolderBlankNameStoresSentinel() async throws {
        let userId = "user-folder-blank"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let id = try await manager.createFolder(name: "   ")
        let folders = try await manager.readFolders()
        XCTAssertEqual(folders.first?.name, RecipeFolderConstants.untitledFolderNameSentinel)
        XCTAssertFalse(id.isEmpty)
    }

    func testRenameFolderUpdatesStoredName() async throws {
        let userId = "user-folder-rename"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let id = try await manager.createFolder(name: "Old")
        try await manager.renameFolder(id: id, name: "New")
        let folders = try await manager.readFolders()
        XCTAssertEqual(folders.first?.name, "New")
    }

    /// T066 [US8]: spec 027 import folder resolution — case-insensitive reuse,
    /// otherwise create.
    ///
    /// History: was `XCTSkipIf(true)`'d because the test host used to perform live
    /// Yjs sync on launch (debug auto-login + Spotlight reindex), stalling the
    /// bundle. The launch-time sync is now gated by `XCTestConfigurationFilePath`
    /// in `AppContainer.bootstrap` (and `AuthService.init`), so the skip is no
    /// longer needed. The test itself is pure in-memory — no live network.
    func testResolveOrCreateFolderReusesCaseInsensitive() async throws {
        let userId = "user-folder-resolve-reuse"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let originalId = try await manager.createFolder(name: "Desserts")
        // Different case + extra whitespace should still match the existing folder.
        let resolvedId = try await manager.resolveOrCreateFolderId(label: "  desserts  ")
        XCTAssertEqual(resolvedId, originalId)

        let folders = try await manager.readFolders()
        XCTAssertEqual(folders.count, 1, "no duplicate folder should be created")
    }

    /// T066 [US8]: when no folder matches, a new one is created.
    func testResolveOrCreateFolderCreatesWhenMissing() async throws {
        let userId = "user-folder-resolve-create"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let newId = try await manager.resolveOrCreateFolderId(label: "Soups")
        XCTAssertFalse(newId.isEmpty)
        let folders = try await manager.readFolders()
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.name, "Soups")
    }

    /// T066 [US8]: blank/whitespace label throws invalid input.
    @MainActor
    func testResolveOrCreateFolderRejectsBlankLabel() async throws {
        let userId = "user-folder-resolve-blank"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        do {
            _ = try await manager.resolveOrCreateFolderId(label: "   ")
            XCTFail("Expected invalidInput")
        } catch RecipeEditError.invalidInput {
            // expected
        } catch {
            XCTFail("Expected invalidInput, got \(error)")
        }
    }

    func testDeleteFolderSoftDeletesAndStripsMembership() async throws {
        let userId = "user-folder-delete"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Pie")

        let folderId = try await manager.createFolder(name: "ToDelete")

        // Attach recipe → folder and verify it persisted.
        try await manager.setRecipeFolders(recipeId: recipeId, folderIds: [folderId])
        var entries = try await manager.readCollectionEntries()
        XCTAssertEqual(entries.first { $0.id == recipeId }?.folderIds, [folderId])

        // Delete folder: entry should be stripped in one transaction.
        try await manager.deleteFolder(id: folderId)

        let folders = try await manager.readFolders()
        XCTAssertTrue(folders.isEmpty, "soft-deleted folder must not appear in active list")

        entries = try await manager.readCollectionEntries()
        let entry = try XCTUnwrap(entries.first { $0.id == recipeId })
        XCTAssertTrue(entry.folderIds.isEmpty, "recipe membership must be stripped")
        XCTAssertFalse(entry.deleted, "recipe itself must remain live")
    }

    func testSetRecipeFoldersValidatesAgainstActiveFolders() async throws {
        let userId = "user-folder-validate"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let recipeId = try await manager.createRecipe(name: "Soup")

        let activeId = try await manager.createFolder(name: "Active")
        let deletedId = try await manager.createFolder(name: "SoonDeleted")
        try await manager.deleteFolder(id: deletedId)

        // Validation: only the active id survives; duplicates are collapsed; invalid ids are dropped.
        try await manager.setRecipeFolders(
            recipeId: recipeId,
            folderIds: [activeId, activeId, deletedId, "does-not-exist", "  "]
        )
        let entries = try await manager.readCollectionEntries()
        XCTAssertEqual(entries.first { $0.id == recipeId }?.folderIds, [activeId])
    }

    func testSetRecipeFoldersRemovesKeyWhenEmpty() async throws {
        let userId = "user-folder-empty"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let folderId = try await manager.createFolder(name: "F")
        let recipeId = try await manager.createRecipe(name: "Cake")

        try await manager.setRecipeFolders(recipeId: recipeId, folderIds: [folderId])
        // After clearing, the Y.Map should no longer carry a `folderIds` key.
        try await manager.setRecipeFolders(recipeId: recipeId, folderIds: [])
        let entries = try await manager.readCollectionEntries()
        let entry = try XCTUnwrap(entries.first { $0.id == recipeId })
        XCTAssertTrue(entry.folderIds.isEmpty)
    }

    func testPinAndTombstoneDoNotStripFolderIds() async throws {
        let userId = "user-folder-preserve"
        let store = try YDocStore.inMemory()
        let manager = DocumentManager(store: store)
        await manager.setUserId(userId)

        let folderId = try await manager.createFolder(name: "F")
        let recipeId = try await manager.createRecipe(name: "Tart")

        try await manager.setRecipeFolders(recipeId: recipeId, folderIds: [folderId])

        // Pin should not strip folderIds (do-no-harm).
        try await manager.setCollectionEntryPinned(recipeId: recipeId, isPinned: true)
        var entries = try await manager.readCollectionEntries()
        XCTAssertEqual(entries.first { $0.id == recipeId }?.folderIds, [folderId])
        XCTAssertTrue(entries.first { $0.id == recipeId }?.isPinned ?? false)

        // Tombstone should preserve folderIds too (web parity).
        try await manager.tombstoneCollectionEntry(recipeId: recipeId)
        let allEntries = try await manager.readCollectionEntries()
        let tombstoned = try XCTUnwrap(allEntries.first { $0.id == recipeId })
        XCTAssertTrue(tombstoned.deleted)
        XCTAssertEqual(tombstoned.folderIds, [folderId])
    }
}

private final class PublicImageCacheTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var callCount = 0

    static func reset() {
        handler = nil
        callCount = 0
    }

    static func incrementCallCount() -> Int {
        callCount += 1
        return callCount
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "public-image-cache-test.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class DescriptionEditorScrollInsetTests: XCTestCase {
    func testContentBottomPaddingEqualsBarClearancePlusBreathingRoomWhenFormattingBarShown() {
        XCTAssertEqual(
            DescriptionFormattingBarLayoutMetrics.contentBottomPadding(showsFormattingBar: true),
            DescriptionFormattingBarLayoutMetrics.scrollClearanceHeight
                + DescriptionFormattingBarLayoutMetrics.contentBottomBreathingRoom
        )
        XCTAssertEqual(
            DescriptionFormattingBarLayoutMetrics.contentBottomPadding(showsFormattingBar: false),
            0
        )
    }

    func testBottomPinnedContentOffsetDoesNotDoubleCountTopInset() {
        // Device-shaped numbers from debug-session 8: pinning caret/editor bottom
        // must use (bounds - insetBottom), not (bounds - insetTop - insetBottom).
        let focusMaxY: CGFloat = 2479
        let boundsHeight: CGFloat = 912
        let insetBottom: CGFloat = 397
        XCTAssertEqual(
            DescriptionFormattingBarLayoutMetrics.bottomPinnedContentOffset(
                focusMaxY: focusMaxY,
                boundsHeight: boundsHeight,
                insetBottom: insetBottom
            ),
            1964,
            accuracy: 0.01
        )
        // Wrong formula (subtracting a ~122pt top inset) would yield ~2086 and
        // leave a ~120pt hole under the last line.
        let wrongVisibleHeight = boundsHeight - 122 - insetBottom
        XCTAssertNotEqual(
            focusMaxY - wrongVisibleHeight,
            DescriptionFormattingBarLayoutMetrics.bottomPinnedContentOffset(
                focusMaxY: focusMaxY,
                boundsHeight: boundsHeight,
                insetBottom: insetBottom
            ),
            accuracy: 0.01
        )
    }

    @MainActor
    func testContentHeightPaintedBottomStoredSeparately() throws {
        let db = try YrsDatabase.makeInMemoryFallback()
        let store = YDocStore(dbQueue: db.dbQueue)
        let sync = YjsSyncService.makeForTesting(store: store)
        let bridge = DescriptionEditorBridge(recipeId: "short-recipe", syncService: sync)

        bridge.handleWebMessage([
            "type": "contentHeight",
            "height": 80,
            "paintedBottom": 72,
            "scrollHeight": 400,
        ])

        XCTAssertEqual(bridge.contentHeight, 80, accuracy: 0.01)
        XCTAssertEqual(bridge.paintedContentBottom, 72, accuracy: 0.01)
    }

    @MainActor
    func testContentHeightMissingPaintedBottomFallsBackToHeight() throws {
        let db = try YrsDatabase.makeInMemoryFallback()
        let store = YDocStore(dbQueue: db.dbQueue)
        let sync = YjsSyncService.makeForTesting(store: store)
        let bridge = DescriptionEditorBridge(recipeId: "short-recipe", syncService: sync)

        bridge.handleWebMessage([
            "type": "contentHeight",
            "height": 64,
        ])

        XCTAssertEqual(bridge.contentHeight, 64, accuracy: 0.01)
        XCTAssertEqual(bridge.paintedContentBottom, 64, accuracy: 0.01)
    }
}
