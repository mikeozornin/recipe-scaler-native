//
//  IOSReleaseNotesCatalog.swift
//  RecipeScalerNative
//
//  Spec 077 — in-app notes catalog compiled into the binary.
//  Do not add a note without an explicit human review from prepare-ios-release.
//  Empty on the mechanism-introducing build so seed never spams existing users.
//

import Foundation

enum IOSReleaseNotesCatalog {
    /// Newest notes may be appended with a strictly greater `version`.
    static let notes: [IOSReleaseNote] = []
}
