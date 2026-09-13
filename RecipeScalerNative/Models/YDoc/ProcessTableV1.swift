import Foundation

/// Wire `Y.Map('recipe').processTable` JSON (schema v1).
struct ProcessTableV1: Equatable, Sendable, Codable {
    struct Column: Equatable, Sendable, Codable {
        enum Kind: String, Equatable, Sendable, Codable {
            case prep
            case cook
        }

        let id: String
        let title: String
        let kind: Kind
        let stepIndex: Int?
    }

    struct Assignment: Equatable, Sendable, Codable {
        let ingredientId: String
        let columnId: String
    }

    struct CellTitle: Equatable, Sendable, Codable {
        let ingredientId: String
        let columnId: String
        let title: String
    }

    let version: Int
    let sourceHash: String
    let columns: [Column]
    let assignments: [Assignment]
    let rowOrder: [String]
    let cellTitles: [CellTitle]

    enum CodingKeys: String, CodingKey {
        case version, sourceHash, columns, assignments, rowOrder, cellTitles
    }

    init(
        version: Int,
        sourceHash: String,
        columns: [Column],
        assignments: [Assignment],
        rowOrder: [String] = [],
        cellTitles: [CellTitle] = []
    ) {
        self.version = version
        self.sourceHash = sourceHash
        self.columns = columns
        self.assignments = assignments
        self.rowOrder = rowOrder
        self.cellTitles = cellTitles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        sourceHash = try container.decode(String.self, forKey: .sourceHash)
        columns = try container.decode([Column].self, forKey: .columns)
        assignments = try container.decode([Assignment].self, forKey: .assignments)
        rowOrder = try container.decodeIfPresent([String].self, forKey: .rowOrder) ?? []
        cellTitles = try container.decodeIfPresent([CellTitle].self, forKey: .cellTitles) ?? []
    }

    /// Returns a valid v1 table or `nil` (missing / invalid / unknown version).
    static func parse(raw: String?) -> ProcessTableV1? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        do {
            let table = try JSONDecoder().decode(ProcessTableV1.self, from: data)
            return table.isValidV1 ? table : nil
        } catch {
            return nil
        }
    }

    var isValidV1: Bool {
        guard version == 1 else { return false }
        guard sourceHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            return false
        }
        guard !columns.isEmpty, !assignments.isEmpty else { return false }
        for column in columns {
            if column.id.isEmpty || column.title.isEmpty { return false }
        }
        for assignment in assignments {
            if assignment.ingredientId.isEmpty || assignment.columnId.isEmpty { return false }
        }
        return true
    }

    var cookColumns: [Column] { columns.filter { $0.kind == .cook } }
    var prepColumns: [Column] { columns.filter { $0.kind == .prep } }

    func isAssigned(ingredientId: String, columnId: String) -> Bool {
        assignments.contains { $0.ingredientId == ingredientId && $0.columnId == columnId }
    }

    func resolvedCellTitle(columnId: String, startIngredientId: String, fallback: String) -> String {
        let match = cellTitles.first {
            $0.columnId == columnId && $0.ingredientId == startIngredientId
        }
        let title = match?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? fallback : title
    }
}

extension RecipeData {
    var processTable: ProcessTableV1? {
        ProcessTableV1.parse(raw: processTableRaw)
    }

    var processTableSourceHash: String {
        ProcessTableSourceHash.hash(ingredients: ingredients, descriptionHtml: description ?? "")
    }

    var isProcessTableStale: Bool {
        guard let table = processTable else { return false }
        return table.sourceHash != processTableSourceHash
    }
}
