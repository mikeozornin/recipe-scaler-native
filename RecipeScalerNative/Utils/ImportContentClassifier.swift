//
//  ImportContentClassifier.swift
//  RecipeScalerNative
//

import Foundation

/// Mirrors `recipe-scaler-web/recipe-scaler/src/utils/import-content.ts`.
enum ImportContentClassifier {

    private static let trailingPunctuation = #/[),.;:!?]+$/#

    /// Extract deduplicated, trimmed URLs from arbitrary free-form text.
    static func extractUrls(from input: String) -> [String] {
        var urls: [String] = []
        var seen = Set<String>()

        let nsRange = NSRange(input.startIndex..., in: input)
        guard let regex = try? NSRegularExpression(
            pattern: "https?://[^\\s<>\"'`]+",
            options: [.caseInsensitive]
        ) else {
            return urls
        }

        for match in regex.matches(in: input, range: nsRange) {
            guard let range = Range(match.range, in: input) else { continue }
            var normalized = String(input[range])
            // Trim trailing punctuation like the web version.
            while let suffixMatch = normalized.firstMatch(of: trailingPunctuation) {
                normalized.removeSubrange(suffixMatch.range)
            }
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(normalized)
        }

        return urls
    }

    /// True if the input has any non-URL, non-noise text content.
    static func hasNonUrlContent(_ input: String) -> Bool {
        let withoutUrls = input.replacingOccurrences(
            of: "https?://[^\\s<>\"'`]+",
            with: " ",
            options: .regularExpression
        )
        let stripped = withoutUrls.replacingOccurrences(
            of: #"[\s.,;:!?()\[\]{}"'`~\-–—_*#+=\\/|<>0-9]+"#,
            with: "",
            options: .regularExpression
        )
        return !stripped.isEmpty
    }

    /// Classify the input into URL-only, mixed text, or plain text.
    /// Equivalent to `classifyImportContent` on the web.
    static func classify(_ input: String) -> Classification {
        let urls = extractUrls(from: input)
        let hasNonUrl = hasNonUrlContent(input)
        return Classification(
            urls: urls,
            hasNonUrlContent: hasNonUrl,
            isUrlOnly: !urls.isEmpty && !hasNonUrl
        )
    }

    struct Classification {
        let urls: [String]
        let hasNonUrlContent: Bool
        let isUrlOnly: Bool
    }
}
