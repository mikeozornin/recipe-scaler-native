//
//  DescriptionBlockLocalizer.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Resolves synthesized structural `DescriptionBlock` signals emitted by
/// Core parsers (`prepTime`, `cookTime`, `durationMinutes`, `difficulty`)
/// into localized paragraphs using the runtime locale.
///
/// Core parsers must remain free of i18n dependencies; this is the single
/// place where third-party import metadata labels cross into user-facing text.
/// Callers MUST run a draft through this before writing into Y.Doc, since
/// `DescriptionXmlFragmentWriter` only handles `.paragraph` / `.heading` /
/// `.orderedListItem`.
enum DescriptionBlockLocalizer {
    static func localize(_ block: DescriptionBlock) -> DescriptionBlock {
        switch block {
        case .paragraph, .heading, .orderedListItem:
            return block
        case .prepTime(let value):
            return .paragraph(String(
                format: Bundle.currentLocalizedString("recipe.import.metadata.prep-time %@"),
                locale: AppLanguagePreference.current.locale,
                value
            ))
        case .cookTime(let value):
            return .paragraph(String(
                format: Bundle.currentLocalizedString("recipe.import.metadata.cook-time %@"),
                locale: AppLanguagePreference.current.locale,
                value
            ))
        case .durationMinutes(let minutes):
            return .paragraph(String(
                format: Bundle.currentLocalizedString("recipe.import.metadata.duration-minutes %d"),
                locale: AppLanguagePreference.current.locale,
                minutes
            ))
        case .difficulty(let value):
            // Free-form value authored by the source recipe's user (e.g. "Easy",
            // "Лёгкий") — not subject to deterministic localization.
            return .paragraph(value)
        }
    }

    static func localize(_ blocks: [DescriptionBlock]) -> [DescriptionBlock] {
        blocks.map(localize)
    }
}
