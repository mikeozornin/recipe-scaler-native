//
//  RecipeDescriptionTimerReference.swift
//  RecipeScalerNative
//

import Foundation
import UIKit

extension NSAttributedString.Key {
    /// Timer span payload (encoded `rs-timer` URL). Not `.link` — avoids blue underline styling.
    static let recipeTimerReference = NSAttributedString.Key("ru.recipescaler.recipeTimerReference")
}

/// Parsed `span.timer-reference` from recipe description HTML.
struct RecipeDescriptionTimerReference: Equatable, Identifiable {
    var id: String {
        "\(durationSeconds)-\(type.rawValue)-\(resolvedName)-\(displayText)"
    }
    let displayText: String
    let durationSeconds: Int
    let type: RecipeTimer.TimerType
    let name: String?

    var isStartable: Bool { durationSeconds > 0 }

    /// Numeric value in the timer's own unit (hours/minutes/seconds), derived from `durationSeconds`.
    /// Matches the web contract in `description-markup-parity.md`:
    ///   hours → durationSeconds / 3600, minutes → /60, seconds → /1.
    var valueAttribute: String {
        let divisor: Int
        switch type {
        case .hours: divisor = 3600
        case .minutes: divisor = 60
        case .seconds: divisor = 1
        }
        let whole = durationSeconds / divisor
        let remainder = durationSeconds % divisor
        if remainder == 0 {
            return String(whole)
        }
        let fractional = Double(remainder) / Double(divisor)
        var text = String(format: "%.4f", Double(whole) + fractional)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    var resolvedName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Web `TimerDropdown` subtitle: `timerDisplayName, timerDuration` or duration text only.
    var menuSubtitle: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            return "\(trimmedName), \(displayText)"
        }
        return displayText
    }

    static let linkScheme = "rs-timer"

    func linkURL() -> URL? {
        guard isStartable else { return nil }
        var items = [
            URLQueryItem(name: "duration", value: "\(durationSeconds)"),
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "text", value: displayText),
        ]
        if let name, !name.isEmpty {
            items.append(URLQueryItem(name: "name", value: name))
        }
        var components = URLComponents()
        components.scheme = Self.linkScheme
        components.queryItems = items
        return components.url
    }

    static func from(link url: URL) -> RecipeDescriptionTimerReference? {
        guard url.scheme == linkScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = components.queryItems
        else { return nil }

        func value(_ key: String) -> String? {
            query.first { $0.name == key }?.value
        }

        guard let durationRaw = value("duration"),
              let duration = Int(durationRaw),
              duration > 0,
              let text = value("text")
        else { return nil }

        let typeRaw = value("type") ?? RecipeTimer.TimerType.minutes.rawValue
        let type = RecipeTimer.TimerType(rawValue: typeRaw) ?? .minutes
        return RecipeDescriptionTimerReference(
            displayText: text,
            durationSeconds: duration,
            type: type,
            name: value("name")
        )
    }
}