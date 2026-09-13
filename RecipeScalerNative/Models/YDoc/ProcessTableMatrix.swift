import Foundation

struct ProcessTableSpan: Equatable, Sendable {
    let startRow: Int
    let rowSpan: Int
}

enum ProcessTableMerge {
    static func consecutiveFilledRows(_ filled: [Bool]) -> [ProcessTableSpan] {
        mergeFilledRowsWithCellTitles(
            filled: filled,
            rowIds: Array(repeating: "", count: filled.count),
            columnId: "",
            cellTitles: []
        )
    }

    static func mergeFilledRowsWithCellTitles(
        filled: [Bool],
        rowIds: [String],
        columnId: String,
        cellTitles: [ProcessTableV1.CellTitle]
    ) -> [ProcessTableSpan] {
        let titleStarts = Set(
            cellTitles.filter { $0.columnId == columnId }.map(\.ingredientId)
        )
        if titleStarts.isEmpty {
            return mergeRuns(filled: filled, rowIds: rowIds, splitOnTitle: false, titleStarts: [])
        }
        return mergeRuns(filled: filled, rowIds: rowIds, splitOnTitle: true, titleStarts: titleStarts)
    }

    private static func mergeRuns(
        filled: [Bool],
        rowIds: [String],
        splitOnTitle: Bool,
        titleStarts: Set<String>
    ) -> [ProcessTableSpan] {
        var spans: [ProcessTableSpan] = []
        var index = 0
        while index < filled.count {
            if filled[index] != true {
                index += 1
                continue
            }
            var end = index
            while end + 1 < filled.count, filled[end + 1] {
                if splitOnTitle {
                    let nextId = end + 1 < rowIds.count ? rowIds[end + 1] : ""
                    if !nextId.isEmpty, titleStarts.contains(nextId) {
                        break
                    }
                }
                end += 1
            }
            spans.append(ProcessTableSpan(startRow: index, rowSpan: end - index + 1))
            index = end + 1
        }
        return spans
    }
}

enum ProcessTableRows {
    static func ordered(ingredients: [IngredientData], rowOrder: [String]) -> [IngredientData] {
        let rows = ingredients.filter { !$0.isSeparator }
        guard !rowOrder.isEmpty else { return rows }
        var byId: [String: IngredientData] = [:]
        for row in rows { byId[row.id] = row }
        var out: [IngredientData] = []
        var used = Set<String>()
        for id in rowOrder {
            if let row = byId[id], used.insert(id).inserted {
                out.append(row)
            }
        }
        for row in rows where !used.contains(row.id) {
            out.append(row)
        }
        return out
    }
}

struct ProcessTableTimerChip: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let duration: Double
    let type: RecipeTimer.TimerType
    let value: Double
    let originalText: String
}

struct ProcessTableTimerMap: Equatable, Sendable {
    var byColumnId: [String: [ProcessTableTimerChip]]
    var leftover: [ProcessTableTimerChip]
}

enum ProcessTableTimers {
    static func map(descriptionHtml: String, columns: [ProcessTableV1.Column]) -> ProcessTableTimerMap {
        var byColumnId: [String: [ProcessTableTimerChip]] = [:]
        var leftover: [ProcessTableTimerChip] = []
        let steps = extractStepInners(descriptionHtml)
        var claimedSteps = Set<Int>()
        let cookColumns = columns.filter { $0.kind == .cook }

        for column in cookColumns {
            guard let stepIndex = column.stepIndex, !claimedSteps.contains(stepIndex) else { continue }
            guard stepIndex >= 0, stepIndex < steps.count else { continue }
            let chips = extractTimerChips(from: steps[stepIndex])
            guard !chips.isEmpty else { continue }
            claimedSteps.insert(stepIndex)
            byColumnId[column.id] = chips
        }

        for (index, inner) in steps.enumerated() {
            if claimedSteps.contains(index) { continue }
            leftover.append(contentsOf: extractTimerChips(from: inner))
        }

        return ProcessTableTimerMap(byColumnId: byColumnId, leftover: leftover)
    }

    static func extractStepInners(_ html: String) -> [String] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let fromList = extractBlocks(from: trimmed, tag: "li")
        if !fromList.isEmpty { return fromList }
        return extractBlocks(from: trimmed, tag: "p")
    }

    static func parseTimerReferenceSpan(_ spanHtml: String) -> ProcessTableTimerChip? {
        guard spanHtml.range(of: #"\btimer-reference\b"#, options: .regularExpression) != nil else {
            return nil
        }
        guard let durationRaw = attr(spanHtml, "data-duration"),
              let typeRaw = attr(spanHtml, "data-type"),
              let type = RecipeTimer.TimerType(rawValue: typeRaw)
        else { return nil }
        guard let duration = Double(durationRaw), duration.isFinite, duration > 0 else { return nil }
        let originalText = ProcessTableSourceHash.decodeBasicEntities(ProcessTableSourceHash.stripTags(spanHtml))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let valueRaw = attr(spanHtml, "data-value")
        let parsedValue = valueRaw.flatMap(Double.init) ?? .nan
        let nameRaw = (attr(spanHtml, "data-name") ?? originalText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = nameRaw.isEmpty ? "Timer" : nameRaw
        let id = attr(spanHtml, "data-timer-id") ?? "\(duration):\(typeRaw):\(name):\(originalText)"
        return ProcessTableTimerChip(
            id: id,
            name: name,
            duration: duration,
            type: type,
            value: parsedValue.isFinite ? parsedValue : duration,
            originalText: originalText
        )
    }

    static func extractTimerChips(from innerHtml: String) -> [ProcessTableTimerChip] {
        guard let regex = try? NSRegularExpression(pattern: #"<span\b[^>]*>[\s\S]*?</span>"#, options: [.caseInsensitive]) else {
            return []
        }
        let ns = innerHtml as NSString
        let matches = regex.matches(in: innerHtml, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { parseTimerReferenceSpan(ns.substring(with: $0.range)) }
    }

    private static func extractBlocks(from html: String, tag: String) -> [String] {
        let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var items: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let inner = ns.substring(with: match.range(at: 1))
            let text = ProcessTableSourceHash.decodeBasicEntities(ProcessTableSourceHash.stripTags(inner))
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            items.append(inner)
        }
        return items
    }

    private static func attr(_ html: String, _ name: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))=[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}

@MainActor
@Observable
final class ProcessTableCookingSession {
    var measuredIngredientIds: Set<String> = []
    var doneCellKeys: Set<String> = []

    func toggleIngredient(_ id: String) {
        if measuredIngredientIds.contains(id) {
            measuredIngredientIds.remove(id)
        } else {
            measuredIngredientIds.insert(id)
        }
    }

    func toggleCell(columnId: String, startIngredientId: String) {
        let key = Self.cellKey(columnId: columnId, startIngredientId: startIngredientId)
        if doneCellKeys.contains(key) {
            doneCellKeys.remove(key)
        } else {
            doneCellKeys.insert(key)
        }
    }

    func isCellDone(columnId: String, startIngredientId: String) -> Bool {
        doneCellKeys.contains(Self.cellKey(columnId: columnId, startIngredientId: startIngredientId))
    }

    static func cellKey(columnId: String, startIngredientId: String) -> String {
        "\(startIngredientId):\(columnId)"
    }
}
