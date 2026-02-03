//
//  ApiCacheEntry.swift
//  RecipeScalerNative
//

import Foundation
import SwiftData

@Model
final class ApiCacheEntry {
    @Attribute(.unique) var key: String
    var etag: String?
    var lastModified: String?
    var lastFetchedAt: Date?

    init(
        key: String,
        etag: String? = nil,
        lastModified: String? = nil,
        lastFetchedAt: Date? = nil
    ) {
        self.key = key
        self.etag = etag
        self.lastModified = lastModified
        self.lastFetchedAt = lastFetchedAt
    }
}

