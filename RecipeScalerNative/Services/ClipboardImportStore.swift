//
//  ClipboardImportStore.swift
//  RecipeScalerNative
//
//  Spec 076 — in-memory clipboard URL-import prompt.
//

import Foundation
import UIKit
import RecipeScalerCore

struct ClipboardImportCandidate: Hashable, Sendable {
    let urls: [String]

    var seedText: String { urls.joined(separator: "\n") }

    static func make(fromPlainText text: String) -> ClipboardImportCandidate? {
        let classification = ImportContentClassifier.classify(text)
        guard classification.isUrlOnly,
              (1...25).contains(classification.urls.count) else {
            return nil
        }
        return ClipboardImportCandidate(urls: classification.urls)
    }
}

enum ClipboardImportBannerState: Equatable {
    case hidden
    case visible
}

struct ClipboardImportEvaluateContext: Equatable {
    var hasSession: Bool
    var isURLImportAvailable: Bool
    var isImportSheetPresented: Bool
    var hasPendingInboundImport: Bool
    var isTransientToastVisible: Bool

    static let eligible = ClipboardImportEvaluateContext(
        hasSession: true,
        isURLImportAvailable: true,
        isImportSheetPresented: false,
        hasPendingInboundImport: false,
        isTransientToastVisible: false
    )
}

protocol ClipboardImportPasteboard: Sendable {
    var changeCount: Int { get }
    func hasProbableWebURL() async -> Bool
    func plainText() async -> String?
}

struct SystemClipboardImportPasteboard: ClipboardImportPasteboard {
    var changeCount: Int { UIPasteboard.general.changeCount }

    func hasProbableWebURL() async -> Bool {
        await withCheckedContinuation { continuation in
            UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                switch result {
                case .success(let patterns):
                    let matched = patterns.contains(.probableWebURL)
                    // iOS 26: detectPatterns(.probableWebURL) can be empty while
                    // URL items still exist. `hasURLs` is metadata and does not
                    // present the Allow Paste prompt; `.string` / `.urls` would.
                    continuation.resume(returning: matched || UIPasteboard.general.hasURLs)
                case .failure:
                    continuation.resume(returning: UIPasteboard.general.hasURLs)
                }
            }
        }
    }

    func plainText() async -> String? {
        if let string = UIPasteboard.general.string,
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string
        }
        if let urls = UIPasteboard.general.urls, !urls.isEmpty {
            return urls.map(\.absoluteString).joined(separator: "\n")
        }
        return UIPasteboard.general.string
    }
}

@MainActor
@Observable
final class ClipboardImportStore {
    private(set) var bannerState: ClipboardImportBannerState = .hidden

    private var dismissedChangeCounts: Set<Int> = []
    private var consumedChangeCounts: Set<Int> = []
    private var ignoredChangeCounts: Set<Int> = []
    private var visibleChangeCount: Int?
    private var pendingConsumeChangeCount: Int?
    private var importSeedTask: Task<String?, Never>?
    private(set) var evaluateGeneration = 0
    private var pasteboard: ClipboardImportPasteboard

    init(pasteboard: ClipboardImportPasteboard = SystemClipboardImportPasteboard()) {
        self.pasteboard = pasteboard
    }

    func replacePasteboard(_ pasteboard: ClipboardImportPasteboard) {
        self.pasteboard = pasteboard
    }

    func ignoreOwnWrite(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
        bannerState = .hidden
        visibleChangeCount = nil
    }

    func dismissVisible() {
        if let changeCount = visibleChangeCount {
            dismissedChangeCounts.insert(changeCount)
        }
        bannerState = .hidden
        visibleChangeCount = nil
    }

    func markConsumed() {
        if let changeCount = pendingConsumeChangeCount ?? visibleChangeCount {
            consumedChangeCounts.insert(changeCount)
        }
        pendingConsumeChangeCount = nil
        bannerState = .hidden
        visibleChangeCount = nil
    }

    func clearForLogout() {
        evaluateGeneration += 1
        importSeedTask?.cancel()
        importSeedTask = nil
        dismissedChangeCounts.removeAll()
        consumedChangeCounts.removeAll()
        ignoredChangeCounts.removeAll()
        pendingConsumeChangeCount = nil
        visibleChangeCount = nil
        bannerState = .hidden
    }

    /// Reads pasteboard contents. Call only from a user gesture (Import tap)
    /// so iOS does not show Allow Paste on every foreground.
    func seedTextForImport() async -> String? {
        let generation = evaluateGeneration
        let changeCount = visibleChangeCount ?? pasteboard.changeCount
        importSeedTask?.cancel()
        let task = Task<String?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            let text = await self.pasteboard.plainText()
            guard !Task.isCancelled, generation == self.evaluateGeneration else { return nil }
            guard let text, let candidate = ClipboardImportCandidate.make(fromPlainText: text) else {
                self.dismissVisible()
                return nil
            }
            self.pendingConsumeChangeCount = changeCount
            return candidate.seedText
        }
        importSeedTask = task
        return await task.value
    }

    func evaluate(context: ClipboardImportEvaluateContext) async {
        evaluateGeneration += 1
        let generation = evaluateGeneration
        let changeCount = pasteboard.changeCount
        let hasURL = await pasteboard.hasProbableWebURL()

        guard generation == evaluateGeneration else { return }
        applySnapshot(
            changeCount: changeCount,
            hasProbableWebURL: hasURL,
            context: context
        )
    }

    /// Sync apply for unit tests. Must not require pasteboard contents.
    func applySnapshot(
        changeCount: Int,
        hasProbableWebURL: Bool,
        context: ClipboardImportEvaluateContext
    ) {
        guard context.hasSession,
              context.isURLImportAvailable,
              !context.isImportSheetPresented,
              !context.hasPendingInboundImport,
              !context.isTransientToastVisible else {
            bannerState = .hidden
            visibleChangeCount = nil
            return
        }
        guard !ignoredChangeCounts.contains(changeCount) else {
            bannerState = .hidden
            visibleChangeCount = nil
            return
        }
        guard hasProbableWebURL else {
            bannerState = .hidden
            visibleChangeCount = nil
            return
        }
        if dismissedChangeCounts.contains(changeCount) || consumedChangeCounts.contains(changeCount) {
            bannerState = .hidden
            visibleChangeCount = nil
            return
        }
        visibleChangeCount = changeCount
        bannerState = .visible
    }
}
