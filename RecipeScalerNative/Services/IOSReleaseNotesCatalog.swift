//
//  IOSReleaseNotesCatalog.swift
//  RecipeScalerNative
//
//  Spec 077 — in-app notes catalog compiled into the binary.
//  Do not add a note without an explicit human review from prepare-ios-release.
//

import Foundation

enum IOSReleaseNotesCatalog {
    /// Newest notes may be appended with a strictly greater `version`.
    static let notes: [IOSReleaseNote] = [
        IOSReleaseNote(
            version: 1,
            date: releaseDate(year: 2026, month: 9, day: 23),
            titleEn: "Follow, hands-free cooking, and Vkusvill",
            titleRu: "Подписки, готовка без рук и Вкусвилл",
            bodyEn: """
            Recipe Scaler is a social network now: you can follow a cook in Discover and read a feed of their new recipes. You can get a notification when they publish.

            Hands-free cooking: when your hands are in the dough, you can scroll the recipe up and down with your voice or gestures.

            From your shopping list, you can build a Vkusvill cart in one tap. All that's left is to place the order.
            """,
            bodyRu: """
            Recipe Scaler стал соцсетью: можно подписаться на автора в Discover и читать ленту его новых рецептов. О публикациях можно получать уведомления.

            Режим готовки без рук: когда руки в тесте, рецепт можно прокручивать вверх и вниз голосом или жестами.

            По списку покупок можно собрать корзину во Вкусвилле в один клик. Вам останется только оформить заказ.
            """
        )
    ]

    private static func releaseDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .gmt
        let parts = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: parts) else {
            preconditionFailure("invalid catalog date \(year)-\(month)-\(day)")
        }
        return date
    }
}
