import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import RecipeScalerNative

/// The perf caches and memos must return what the uncached code returned.
@MainActor
final class UIPerfCachingTests: XCTestCase {

    // MARK: - Assistant message rows

    func testMessageRenderEqualityComparesEveryRenderedField() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let base = message(text: "Сними с огня", createdAt: createdAt)

        XCTAssertTrue(AssistantMessageRenderEquality.isEqual(base, base))

        var changed = base
        changed.text += "!"
        XCTAssertFalse(AssistantMessageRenderEquality.isEqual(base, changed))

        changed = base
        changed.isStreaming = true
        XCTAssertFalse(AssistantMessageRenderEquality.isEqual(base, changed))

        changed = base
        changed.role = "user"
        XCTAssertFalse(AssistantMessageRenderEquality.isEqual(base, changed))

        changed = base
        changed.createdAt = createdAt.addingTimeInterval(60)
        XCTAssertFalse(AssistantMessageRenderEquality.isEqual(base, changed))

        changed = base
        changed.metadata = .toolStatusOnly(toolName: "search_recipes")
        XCTAssertFalse(AssistantMessageRenderEquality.isEqual(base, changed))
    }

    func testMessageRenderEqualityComparesMetadataByValue() {
        func metadata(name: String) -> AssistantMessageMetadata {
            AssistantMessageMetadata(
                attachments: [
                    AssistantRecipeAttachment(recipeId: "r1", recipeName: name, recipeColor: "#ff0000"),
                ],
                followUpSuggestions: nil
            )
        }
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        var lhs = message(text: "", createdAt: createdAt)
        var rhs = lhs
        lhs.metadata = metadata(name: "Борщ")
        rhs.metadata = metadata(name: "Борщ")
        // Built separately: different storage, same value.
        XCTAssertTrue(AssistantMessageRenderEquality.isEqual(lhs, rhs))

        rhs.metadata = metadata(name: "Щи")
        XCTAssertFalse(AssistantMessageRenderEquality.isEqual(lhs, rhs))

        rhs.metadata = .toolStatusOnly(toolName: "a")
        lhs.metadata = .toolStatusOnly(toolName: "a")
        XCTAssertTrue(AssistantMessageRenderEquality.isEqual(lhs, rhs))
        lhs.metadata = .toolStatusOnly(toolName: "b")
        XCTAssertFalse(AssistantMessageRenderEquality.isEqual(lhs, rhs))
    }

    func testAttachableLookupsMemoMatchesBuild() {
        let memo = AssistantAttachableRecipeLookupsMemo()
        var entries = [entry(id: "a", name: "Борщ"), entry(id: "b", name: "")]

        XCTAssertEqual(memo.lookups(for: entries), AssistantAttachableRecipeLookups.build(from: entries))
        XCTAssertEqual(memo.lookups(for: entries), AssistantAttachableRecipeLookups.build(from: entries))

        entries.append(entry(id: "c", name: "Щи", color: "#00ff00"))
        XCTAssertEqual(memo.lookups(for: entries), AssistantAttachableRecipeLookups.build(from: entries))
    }

    // MARK: - Timestamps

    func testTimestampsMatchFreshFormatters() {
        let now = Date()
        let dates = [
            now.addingTimeInterval(-60),
            now.addingTimeInterval(-86_400),
            now.addingTimeInterval(-3 * 86_400),
            now.addingTimeInterval(-40 * 86_400),
            now.addingTimeInterval(-400 * 86_400),
        ]
        for identifier in ["ru_RU", "en_US", "en_GB"] {
            let locale = Locale(identifier: identifier)
            for date in dates {
                let expected = legacyTimestamp(createdAt: date, locale: locale)
                XCTAssertEqual(AssistantMessageTimestampFormatter.format(createdAt: date, locale: locale), expected)
                // Second call is served from the cache.
                XCTAssertEqual(AssistantMessageTimestampFormatter.format(createdAt: date, locale: locale), expected)
            }
        }
    }

    func testTimestampFormatterIsReused() {
        let cache = AssistantTimestampFormatterCache()
        let locale = Locale(identifier: "ru_RU")
        XCTAssertTrue(cache.formatter(.time, locale: locale) === cache.formatter(.time, locale: locale))
        XCTAssertFalse(cache.formatter(.time, locale: locale) === cache.formatter(.monthDayYear, locale: locale))
        let first = cache.formatter(.monthDayTime, locale: locale)
        cache.removeAll()
        XCTAssertFalse(first === cache.formatter(.monthDayTime, locale: locale))
    }

    // MARK: - Fonts

    func testCachedUIFontsMatchFreshResolution() {
        let cases: [(name: String, size: CGFloat, fallback: String)] = [
            (AppFonts.sans, AppTypography.bodySize, AppFonts.sans),
            (AppFonts.sansMedium, AppTypography.bodySize, AppFonts.sansMedium),
            (AppFonts.display, AppTypography.title2Size, AppFonts.display),
            (AppFonts.mono, AppTypography.footnoteSize, AppFonts.mono),
            (AppFonts.sans, 13.5, AppFonts.sans),
        ]
        for item in cases {
            let first = AppTypography.uiFont(item.name, size: item.size, fallbackFamily: item.fallback)
            let second = AppTypography.uiFont(item.name, size: item.size, fallbackFamily: item.fallback)
            let fresh = legacyUIFont(item.name, size: item.size, fallbackFamily: item.fallback)
            XCTAssertTrue(first === second, item.name)
            XCTAssertEqual(first.fontName, fresh.fontName)
            XCTAssertEqual(first.pointSize, fresh.pointSize)
            XCTAssertTrue(first.fontName.hasPrefix("Martian"), first.fontName)
        }
        XCTAssertEqual(AppTypography.bodyUIFont.fontName, legacyUIFont(AppFonts.sans, size: AppTypography.bodySize).fontName)
    }

    func testTextStylesKeepTheirFonts() {
        XCTAssertEqual(AppTypography.body, AppTypography.body)
        XCTAssertEqual(AppTypography.body, AppTypography.sans(AppTypography.bodySize))
        XCTAssertEqual(AppTypography.headline, AppTypography.sansMedium(AppTypography.bodySize))
        XCTAssertEqual(AppTypography.title2, AppTypography.display(AppTypography.title2Size))
        XCTAssertNotEqual(AppTypography.body, AppTypography.footnote)
        XCTAssertNotEqual(AppTypography.body, AppTypography.headline)
    }

    func testItalicFontMatchesFreshResolution() {
        for typography in [RecipeDescriptionBlockTypography.body, .heading(level: 1)] {
            let family: String
            switch typography {
            case .body: family = AppFonts.sans
            case .heading: family = AppFonts.display
            }
            let size = typography.fontSize
            let fresh = UIFont(name: family, size: size)?
                .fontDescriptor
                .withSymbolicTraits(.traitItalic)
                .map { UIFont(descriptor: $0, size: size) }
            let cached = typography.italicFont
            XCTAssertEqual(cached?.fontName, fresh?.fontName)
            XCTAssertEqual(cached?.pointSize, fresh?.pointSize)
            XCTAssertEqual(typography.italicFont?.fontName, fresh?.fontName)
        }
    }

    // MARK: - Guide assets

    func testGuideImageLookupMatchesBundle() {
        var names = GuideAssetResolver.candidateNames(forBaseName: "guide_sent_assistant_message_ex_01")
        names += GuideAssetResolver.candidateNames(forBaseName: "AppLogo")
        names.append("guide_missing_asset_for_tests")
        var foundAny = false
        for name in names {
            let exists = UIImage(named: name) != nil
            foundAny = foundAny || exists
            XCTAssertEqual(GuideAssetResolver.hasBundledImage(named: name), exists, name)
            XCTAssertEqual(GuideAssetResolver.hasBundledImage(named: name), exists, name)
        }
        XCTAssertTrue(foundAny)
        XCTAssertTrue(GuideAssetResolver.hasImage(forBaseName: "AppLogo"))
        XCTAssertNotNil(GuideAssetResolver.image(forBaseName: "AppLogo"))
        XCTAssertFalse(GuideAssetResolver.hasImage(forBaseName: "guide_missing_asset_for_tests"))
    }

    // MARK: - Awake scroll help

    func testPulseClockWakesOnceWhenHighlightEnds() throws {
        let pulse = Date(timeIntervalSince1970: 1_700_000_000)
        let duration = AwakeScrollLayout.helpDebugFiredDuration

        XCTAssertNil(AwakeScrollPulseClockTiming.delayUntilExpiry(of: nil, now: pulse))
        XCTAssertNil(AwakeScrollPulseClockTiming.delayUntilExpiry(of: pulse, now: pulse.addingTimeInterval(duration + 0.001)))
        XCTAssertNil(AwakeScrollPulseClockTiming.delayUntilExpiry(of: pulse, now: pulse.addingTimeInterval(5)))

        let now = pulse.addingTimeInterval(0.3)
        let delay = try XCTUnwrap(AwakeScrollPulseClockTiming.delayUntilExpiry(of: pulse, now: now))
        XCTAssertEqual(delay, duration - 0.3 + 0.01, accuracy: 0.000_1)
        // On wake the fired check (`< duration`) is already false.
        XCTAssertFalse(now.addingTimeInterval(delay).timeIntervalSince(pulse) < duration)
    }

    // MARK: - Collapsed timer summary

    func testCollapsedSummaryTicksOnlyWhileATimerCountsDown() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let ticking = Array(CollapsedTimerSummarySchedule(isTicking: true).entries(from: start, mode: .normal).prefix(3))
        XCTAssertEqual(ticking, [start, start.addingTimeInterval(1), start.addingTimeInterval(2)])

        let still = Array(CollapsedTimerSummarySchedule(isTicking: false).entries(from: start, mode: .normal).prefix(3))
        XCTAssertEqual(still, [start])

        let running = timer(isRunning: true, isPaused: false)
        let paused = timer(isRunning: true, isPaused: true)
        let stopped = timer(isRunning: false, isPaused: false)
        XCTAssertTrue(CollapsedTimerSummarySchedule(timers: [paused, running]).isTicking)
        XCTAssertFalse(CollapsedTimerSummarySchedule(timers: [paused, stopped]).isTicking)
        XCTAssertFalse(CollapsedTimerSummarySchedule(timers: []).isTicking)
    }

    // MARK: - Recipe picker

    func testRecipePickerResultsMatchLegacyFilter() {
        var entries = [
            entry(id: "1", name: "Château Margaux"),
            entry(id: "2", name: "Борщ украинский"),
            entry(id: "3", name: "Pinot Toscana red"),
            entry(id: "4", name: "pinot noir"),
            entry(id: "5", name: "Йогурт с мёдом"),
            entry(id: "6", name: "Red pinot, toscana"),
        ]
        entries += (0 ..< 60).map { entry(id: "soup-\($0)", name: "Soup \($0)") }
        let normalized = AssistantRecipePickerNormalizedNames().names(for: entries)
        let queries = [
            "", "   ", "p", "P", "PINOT", "chateau", "Château", "CHÂTEAU", "pinot toscana",
            "\"pinot toscana\"", "red \"pinot toscana\"", "\"\"", "soup", " soup 1 ", "борщ",
            "БОРЩ", "йог", "мед", "xyz", "\"red pinot",
        ]
        let attachmentSets: [[AssistantRecipeAttachment]] = [
            [],
            [AssistantRecipeAttachment(recipeId: "3", recipeName: nil, recipeColor: nil)],
            [
                AssistantRecipeAttachment(recipeId: "soup-0", recipeName: nil, recipeColor: nil),
                AssistantRecipeAttachment(recipeId: "1", recipeName: nil, recipeColor: nil),
            ],
        ]
        for attachments in attachmentSets {
            for query in queries {
                let results = AssistantRecipePickerFilter.results(
                    entries: entries,
                    normalizedNames: normalized,
                    attachments: attachments,
                    query: query
                )
                let legacy = legacyPickerResults(entries: entries, attachments: attachments, query: query)
                XCTAssertEqual(results.attachable, legacy.attachable, query)
                XCTAssertEqual(results.filtered, legacy.filtered, query)
            }
        }
    }

    func testPickerNormalizedNamesFollowEntries() {
        let memo = AssistantRecipePickerNormalizedNames()
        var entries = [entry(id: "1", name: "Château"), entry(id: "2", name: "Борщ")]
        XCTAssertEqual(memo.names(for: entries), entries.map { RecipeSearchUtils.normalizeForSearch($0.name) })
        entries.append(entry(id: "3", name: "Crème brûlée"))
        XCTAssertEqual(memo.names(for: entries), entries.map { RecipeSearchUtils.normalizeForSearch($0.name) })
    }

    // MARK: - Shopping list

    func testAlphabetSortMatchesLegacyComparator() {
        let labels = [
            "200 г · мука", "сахар", "  1 шт · Яйцо ", "мука", "Apple", "apple", "Мука",
            "3 ст. л. · масло", "масло", " · ", "", "ёжевика", "Ежевика", "10 г · соль", "соль",
            "2 · сахар", "яблоко", "Banana", "banana · ", "Çay",
        ]
        let items = (labels + labels).enumerated().map { index, label in
            ShoppingListItem(id: "item-\(index)", label: label)
        }
        let legacy = items.sorted {
            ShoppingListFromRecipe.sortName(for: $0.label)
                .localizedCompare(ShoppingListFromRecipe.sortName(for: $1.label)) == .orderedAscending
        }
        XCTAssertEqual(ShoppingViewModel.sortedAlphabetically(items).map(\.id), legacy.map(\.id))
        XCTAssertEqual(ShoppingViewModel.sortedAlphabetically([]).map(\.id), [])
    }

    // MARK: - Recipe description

    /// The description starts in TextKit 1 and keeps one highlight per timer across layout passes.
    /// Built through `UITextView(usingTextLayoutManager:)`, its stored properties were never set
    /// and the first `layoutSubviews` crashed.
    func testDescriptionLaysOutTimerHighlightsInTextKit1() throws {
        let timer = RecipeDescriptionTimerReference(
            displayText: "30 minutes", durationSeconds: 1800, type: .minutes, name: nil
        )
        let description = RecipeDescriptionInlineTextView(
            runs: [.plain("Bake for "), .timer(timer), .plain(", then let it cool on a rack.")],
            accentColor: .orange
        )
        let host = UIHostingController(rootView: description.frame(width: 320))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.view.layoutIfNeeded()

        let textView = try XCTUnwrap(firstTextView(in: host.view))
        XCTAssertNil(textView.textLayoutManager)
        XCTAssertEqual(textView.attributedText.string, "Bake for 30 minutes, then let it cool on a rack.")
        XCTAssertGreaterThan(textView.bounds.height, 0)
        let canvas = textView.subviews.first ?? textView
        let highlights = { (canvas.layer.sublayers ?? []).filter { $0 is CAShapeLayer }.count }
        XCTAssertEqual(highlights(), 1)
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        XCTAssertEqual(highlights(), 1)
    }

    // MARK: - Helpers

    private func firstTextView(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) { return textView }
        }
        return nil
    }

    private func message(text: String, createdAt: Date) -> AssistantMessage {
        AssistantMessage(
            id: "assistant-1",
            role: "assistant",
            text: text,
            isStreaming: false,
            metadata: nil,
            createdAt: createdAt
        )
    }

    private func entry(id: String, name: String, color: String = "#ff0000") -> CollectionEntry {
        CollectionEntry(
            id: id,
            name: name,
            color: color,
            imageUrl: nil,
            updatedAt: "2026-01-01T00:00:00Z",
            deleted: false,
            isPinned: false
        )
    }

    private func timer(isRunning: Bool, isPaused: Bool) -> RecipeTimer {
        let timer = RecipeTimer(
            id: "summary-\(isRunning)-\(isPaused)",
            name: "Test",
            duration: 120,
            type: .minutes,
            isRunning: isRunning,
            isPaused: isPaused
        )
        timer.endTime = Date().addingTimeInterval(60)
        return timer
    }

    /// The timestamp code before the formatter cache.
    private func legacyTimestamp(createdAt: Date, locale: Locale) -> String {
        let calendar = Calendar.current
        let now = Date()

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        if calendar.isDate(createdAt, inSameDayAs: now) {
            return timeFormatter.string(from: createdAt)
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(createdAt, inSameDayAs: yesterday) {
            let yesterdayLabel = Bundle.currentLocalizedString("assistant.timestamp.yesterday")
            return "\(yesterdayLabel), \(timeFormatter.string(from: createdAt))"
        }

        if calendar.component(.year, from: createdAt) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("MMMdHHmm")
            return formatter.string(from: createdAt)
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter.string(from: createdAt)
    }

    /// Font resolution before the cache.
    private func legacyUIFont(_ name: String, size: CGFloat, fallbackFamily: String = AppFonts.sans) -> UIFont {
        AppFonts.registerBundledFontsIfNeeded()
        func resolve(_ face: String) -> UIFont? {
            UIFont(name: face, size: size)
                ?? AppFonts.postScriptName(for: face).flatMap { UIFont(name: $0, size: size) }
        }
        return resolve(name) ?? resolve(fallbackFamily) ?? resolve(AppFonts.sans) ?? .systemFont(ofSize: size)
    }

    /// The picker filtering before it was computed once per pass.
    private func legacyPickerResults(
        entries: [CollectionEntry],
        attachments: [AssistantRecipeAttachment],
        query: String
    ) -> (attachable: [CollectionEntry], filtered: [CollectionEntry]) {
        let attachable = entries.filter { entry in
            !attachments.contains { $0.recipeId == entry.id }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (attachable, Array(attachable.prefix(50))) }
        let tokens = RecipeSearchUtils.tokenizeQuery(trimmed)
        guard !tokens.isEmpty else { return (attachable, []) }
        let filtered = attachable
            .filter { RecipeSearchUtils.matchesName($0.name, tokens: tokens) }
            .prefix(50)
            .map { $0 }
        return (attachable, filtered)
    }
}
