//
//  ShoppingListPlainText.swift
//  RecipeScalerNative
//

import Foundation

enum ShoppingListPlainText {
    private static let miscKey = "__misc__"

    struct Headings {
        var misc: String
        var untitledRecipe: String
    }

    static func build(
        items: [ShoppingListItem],
        headings: Headings,
        sortMode: ShoppingSortMode
    ) -> String {
        let nonEmpty = items.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return "" }

        if sortMode == .alphabet {
            return nonEmpty
                .map { "- \($0.label.trimmingCharacters(in: .whitespacesAndNewlines))" }
                .joined(separator: "\n")
        }

        var byKey: [String: [ShoppingListItem]] = [:]
        for item in nonEmpty {
            let key = item.recipeId ?? miscKey
            byKey[key, default: []].append(item)
        }

        struct Group {
            let title: String
            let sortKey: String
            let sortId: String
            let lines: [String]
        }

        var groups: [Group] = []
        for (key, groupItems) in byKey {
            let title: String
            if key == miscKey {
                title = headings.misc
            } else {
                title = groupItems
                    .map(\.recipeName)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? headings.untitledRecipe
            }

            let lines = groupItems
                .map { item in
                    (
                        label: item.label.trimmingCharacters(in: .whitespacesAndNewlines),
                        sortLabel: ShoppingListFromRecipe.sortName(for: item.label).lowercased(),
                        id: item.id
                    )
                }
                .sorted { lhs, rhs in
                    let c = lhs.sortLabel.localizedCompare(rhs.sortLabel)
                    if c != .orderedSame { return c == .orderedAscending }
                    return lhs.id < rhs.id
                }
                .map { "- \($0.label)" }

            groups.append(
                Group(
                    title: title,
                    sortKey: title.lowercased(),
                    sortId: key,
                    lines: lines
                )
            )
        }

        groups.sort { lhs, rhs in
            let c = lhs.sortKey.localizedCompare(rhs.sortKey)
            if c != .orderedSame { return c == .orderedAscending }
            return lhs.sortId < rhs.sortId
        }

        return groups.map { "\($0.title)\n\($0.lines.joined(separator: "\n"))" }.joined(separator: "\n\n")
    }
}

enum ShoppingFeedback {
    static func postStatus(_ message: String) {
        NotificationCenter.default.post(name: .shoppingStatusMessage, object: message)
        #if DEBUG
        writeVerifyRecord(message)
        #endif
    }

    #if DEBUG
    static func verifyRecordURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("shopping-toast-verify.json")
    }

    private static func writeVerifyRecord(_ message: String) {
        let payload: [String: String] = [
            "message": message,
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: verifyRecordURL(), options: .atomic)
    }
    #endif
}

enum ShoppingAddFeedback {
    static func message(for count: Int) -> String {
        if count == 1 {
            return String(localized: "shopping.items-added.one")
        }
        return String(format: String(localized: "shopping.items-added.many"), count)
    }
}

extension Notification.Name {
    static let openAppShoppingTab = Notification.Name("RecipeScaler.openAppShoppingTab")
    static let shoppingStatusMessage = Notification.Name("RecipeScaler.shoppingStatusMessage")
}