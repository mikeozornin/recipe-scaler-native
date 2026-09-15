//
//  IOSReleaseNote.swift
//  RecipeScalerNative
//
//  Spec 077 — one in-app release note shipped in the iOS binary.
//  Not a web catalog row and not App Store What’s New.
//

import Foundation

public struct IOSReleaseNote: Equatable, Identifiable, Sendable {
    public let version: Int
    public let date: Date
    public let titleEn: String
    public let titleRu: String
    public let bodyEn: String
    public let bodyRu: String

    public var id: Int { version }

    public init(
        version: Int,
        date: Date,
        titleEn: String,
        titleRu: String,
        bodyEn: String,
        bodyRu: String
    ) {
        self.version = version
        self.date = date
        self.titleEn = titleEn
        self.titleRu = titleRu
        self.bodyEn = bodyEn
        self.bodyRu = bodyRu
    }

    public func title(for languageCode: String) -> String {
        languageCode.hasPrefix("ru") ? titleRu : titleEn
    }

    public func body(for languageCode: String) -> String {
        languageCode.hasPrefix("ru") ? bodyRu : bodyEn
    }
}
