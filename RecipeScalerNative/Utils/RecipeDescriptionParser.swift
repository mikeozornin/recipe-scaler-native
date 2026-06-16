//
//  RecipeDescriptionParser.swift
//  RecipeScalerNative
//
//  Fast HTML → native blocks (no NSAttributedString HTML import).
//

import Foundation

struct RecipeDescriptionDocument: Equatable {
    let blocks: [RecipeDescriptionBlock]
}

enum RecipeDescriptionBlock: Equatable, Identifiable {
    case paragraph(id: UUID, runs: [RecipeDescriptionInlineRun])
    case orderedStep(id: UUID, number: Int, runs: [RecipeDescriptionInlineRun])
    case bullet(id: UUID, runs: [RecipeDescriptionInlineRun])
    case heading(id: UUID, level: Int, runs: [RecipeDescriptionInlineRun])

    var id: UUID {
        switch self {
        case .paragraph(let id, _), .orderedStep(let id, _, _), .bullet(let id, _), .heading(let id, _, _):
            return id
        }
    }
}

enum RecipeDescriptionInlineRun: Equatable {
    case plain(String)
    case strong(String)
    case em(String)
    case link(url: String, text: String)
    case timer(RecipeDescriptionTimerReference)
    case ingredient(id: String?, ratio: Double?, originalAmount: String?, text: String)
    case lineBreak

    /// Plain-text flattening (search indexing, fallback rendering).
    var flattenedText: String? {
        switch self {
        case .plain(let text), .strong(let text), .em(let text):
            return text
        case .link(_, let text):
            return text
        case .timer(let reference):
            return reference.displayText
        case .ingredient(_, _, _, let text):
            return text
        case .lineBreak:
            return nil
        }
    }
}

enum RecipeDescriptionParser {
    static func parse(_ html: String) -> RecipeDescriptionDocument {
        let normalized = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var blocks: [RecipeDescriptionBlock] = []
        var cursor = normalized.startIndex
        var stepNumber = 0

        while cursor < normalized.endIndex {
            if let match = firstBlockTag(in: normalized, from: cursor) {
                if match.range.lowerBound > cursor {
                    appendParagraphIfNeeded(
                        String(normalized[cursor..<match.range.lowerBound]),
                        into: &blocks
                    )
                }
                let inner = match.inner
                switch match.name {
                case "ol":
                    stepNumber = 0
                    blocks.append(contentsOf: parseOrderedList(inner, stepOffset: &stepNumber))
                case "ul":
                    blocks.append(contentsOf: parseBulletList(inner))
                case "p":
                    if let runs = parseInline(inner), !runs.isEmpty {
                        blocks.append(.paragraph(id: UUID(), runs: runs))
                    }
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    let level = Int(match.name.dropFirst()) ?? 1
                    if let runs = parseInline(inner), !runs.isEmpty {
                        blocks.append(.heading(id: UUID(), level: level, runs: runs))
                    }
                default:
                    break
                }
                cursor = match.range.upperBound
            } else {
                appendParagraphIfNeeded(String(normalized[cursor...]), into: &blocks)
                break
            }
        }

        return RecipeDescriptionDocument(blocks: blocks)
    }

    // MARK: - Block extraction

    private struct BlockTagMatch {
        let name: String
        let inner: String
        let range: Range<String.Index>
    }

    private static func firstBlockTag(in html: String, from start: String.Index) -> BlockTagMatch? {
        let pattern = #"<(ol|ul|p|h[1-6])(?:\s[^>]*)?>([\s\S]*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let substring = String(html[start...])
        let subNS = substring as NSString
        guard let match = regex.firstMatch(in: substring, range: NSRange(location: 0, length: subNS.length)) else {
            return nil
        }
        let name = subNS.substring(with: match.range(at: 1)).lowercased()
        let inner = subNS.substring(with: match.range(at: 2))
        let rangeStart = html.index(start, offsetBy: match.range.location)
        let rangeEnd = html.index(rangeStart, offsetBy: match.range.length)
        return BlockTagMatch(name: name, inner: inner, range: rangeStart..<rangeEnd)
    }

    private static func parseOrderedList(_ html: String, stepOffset: inout Int) -> [RecipeDescriptionBlock] {
        liContents(html).map { item -> RecipeDescriptionBlock in
            stepOffset += 1
            let runs = parseInline(unwrapParagraph(item)) ?? []
            return .orderedStep(id: UUID(), number: stepOffset, runs: runs)
        }
    }

    private static func parseBulletList(_ html: String) -> [RecipeDescriptionBlock] {
        liContents(html).map { item -> RecipeDescriptionBlock in
            let runs = parseInline(unwrapParagraph(item)) ?? []
            return .bullet(id: UUID(), runs: runs)
        }
    }

    private static func liContents(_ html: String) -> [String] {
        let pattern = #"<li[^>]*>([\s\S]*?)</li>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    private static func unwrapParagraph(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^<p[^>]*>([\s\S]*?)</p>$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)),
              match.numberOfRanges > 1
        else { return trimmed }
        return (trimmed as NSString).substring(with: match.range(at: 1))
    }

    private static func appendParagraphIfNeeded(_ raw: String, into blocks: inout [RecipeDescriptionBlock]) {
        let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return }
        if let runs = parseInline(raw), !runs.isEmpty {
            blocks.append(.paragraph(id: UUID(), runs: runs))
        }
    }

    // MARK: - Inline

    static func parseInline(_ html: String) -> [RecipeDescriptionInlineRun]? {
        var runs: [RecipeDescriptionInlineRun] = []
        parseInlineNodes(html, into: &runs)
        let merged = mergePlainRuns(runs)
        return merged.isEmpty ? nil : merged
    }

    private static func parseInlineNodes(_ html: String, into runs: inout [RecipeDescriptionInlineRun]) {
        var index = html.startIndex
        while index < html.endIndex {
            guard let open = html[index...].range(of: "<") else {
                appendPlain(String(html[index...]), into: &runs)
                break
            }
            if open.lowerBound > index {
                appendPlain(String(html[index..<open.lowerBound]), into: &runs)
            }

            let tagStart = open.lowerBound
            guard let close = html[tagStart...].range(of: ">") else {
                appendPlain(String(html[tagStart...]), into: &runs)
                break
            }
            let tagSource = String(html[tagStart..<close.upperBound])

            if tagSource.hasPrefix("<br") {
                runs.append(.lineBreak)
                index = close.upperBound
                continue
            }
            if tagSource.hasPrefix("</") {
                index = close.upperBound
                continue
            }

            guard let tagName = tagName(from: tagSource) else {
                appendPlain(tagSource, into: &runs)
                index = close.upperBound
                continue
            }

            let pattern = #"<\#(tagName)(?:\s[^>]*)?>([\s\S]*?)</\#(tagName)>"#
            let search = String(html[tagStart...])
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: search, range: NSRange(location: 0, length: (search as NSString).length))
            else {
                appendPlain(tagSource, into: &runs)
                index = close.upperBound
                continue
            }
            let inner = (search as NSString).substring(with: match.range(at: 1))
            index = html.index(tagStart, offsetBy: match.range.length)

            switch tagName.lowercased() {
            case "a":
                let href = attribute(named: "href", in: tagSource) ?? ""
                let text = stripTags(inner)
                if !text.isEmpty {
                    runs.append(.link(url: href, text: text))
                }
            case "span":
                if tagSource.contains("timer-reference") {
                    let text = stripTags(inner)
                    if !text.isEmpty {
                        let durationSeconds = Int(attribute(named: "data-duration", in: tagSource) ?? "") ?? 0
                        let typeRaw = attribute(named: "data-type", in: tagSource) ?? RecipeTimer.TimerType.minutes.rawValue
                        let type = RecipeTimer.TimerType(rawValue: typeRaw) ?? .minutes
                        let name = attribute(named: "data-name", in: tagSource)
                        runs.append(
                            .timer(
                                RecipeDescriptionTimerReference(
                                    displayText: text,
                                    durationSeconds: durationSeconds,
                                    type: type,
                                    name: name
                                )
                            )
                        )
                    }
                } else if tagSource.contains("ingredient-reference") {
                    let text = stripTags(inner)
                    if !text.isEmpty {
                        let id = attribute(named: "data-ingredient-id", in: tagSource)
                        let ratio = attribute(named: "data-ratio", in: tagSource).flatMap(Double.init)
                        let originalAmount = attribute(named: "data-original-amount", in: tagSource)
                        runs.append(.ingredient(id: id, ratio: ratio, originalAmount: originalAmount, text: text))
                    }
                } else {
                    parseInlineNodes(inner, into: &runs)
                }
            case "strong", "b":
                let text = stripTags(inner)
                if !text.isEmpty { runs.append(.strong(text)) }
            case "em", "i":
                let text = stripTags(inner)
                if !text.isEmpty { runs.append(.em(text)) }
            default:
                parseInlineNodes(inner, into: &runs)
            }
        }
    }

    private static func tagName(from tag: String) -> String? {
        let pattern = #"^<([a-zA-Z][a-zA-Z0-9]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)),
              match.numberOfRanges > 1
        else { return nil }
        return (tag as NSString).substring(with: match.range(at: 1))
    }

    private static func attribute(named name: String, in tag: String) -> String? {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)),
              match.numberOfRanges > 1
        else { return nil }
        return (tag as NSString).substring(with: match.range(at: 1))
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func appendPlain(_ text: String, into runs: inout [RecipeDescriptionInlineRun]) {
        let decoded = stripTags(text)
        guard !decoded.isEmpty else { return }
        runs.append(.plain(decoded))
    }

    private static func mergePlainRuns(_ runs: [RecipeDescriptionInlineRun]) -> [RecipeDescriptionInlineRun] {
        var merged: [RecipeDescriptionInlineRun] = []
        for run in runs {
            if case .plain(let a) = run, case .plain(let b)? = merged.last {
                merged[merged.count - 1] = .plain(a + b)
            } else {
                merged.append(run)
            }
        }
        return merged
    }
}