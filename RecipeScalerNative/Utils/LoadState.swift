//
//  LoadState.swift
//  RecipeScalerNative
//

import Foundation

/// Generic async load lifecycle for feature view models.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}
