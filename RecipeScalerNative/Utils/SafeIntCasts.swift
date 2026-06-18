//
//  SafeIntCasts.swift
//  RecipeScalerNative
//
//  Defense against Swift precondition traps on `Int(someDouble)` (review #14):
//  when `someDouble` is NaN, Infinity, or outside Int64 range, `Int(value)`
//  traps (hard crash) instead of throwing. These casts are safe.
//
//  Prefer the shared helper `IngredientData.formatScalarNumber(_:)` for
//  UI formatting use-cases (returns "" for NaN/Inf, smartly picks
//  integer vs decimal representation). Use the cast helpers below only
//  when an actual `Int` is required (servings math, duration seconds,
//  Socket.IO byte arrays).
//

import Foundation

extension Int {
    /// Returns `nil` when `value` is NaN/Infinity or not representable as `Int`.
    ///
    /// Use for "is this exactly an integer?" checks where precision loss is
    /// unacceptable — the caller decides the fallback path.
    init?(exactlySafe value: Double) {
        guard value.isFinite,
              abs(value) < Double(Int.max),
              let intValue = Int(exactly: value) else {
            return nil
        }
        self = intValue
    }

    /// Clamps `value` to `Int.min...Int.max`; NaN/Infinity become 0.
    ///
    /// Use for bounded-domain values where the caller would rather have a
    /// representable Int than crash (servings, durations in seconds, ratio
    /// percentages). Rejected inputs are mapped to the lower bound of the
    /// domain separately by the caller.
    init(clampingFinite value: Double) {
        if value.isNaN || value.isInfinite {
            self = 0
            return
        }
        if value >= Double(Int.max) {
            self = Int.max
            return
        }
        if value <= Double(Int.min) {
            self = Int.min
            return
        }
        self = Int(value)
    }
}

extension Int64 {
    /// Clamps `value` to `Int64.min...Int64.max`; NaN/Infinity become 0.
    ///
    /// Stdlib `init(clamping:)` only accepts `BinaryInteger`, not floating point.
    /// This is the Double-friendly counterpart for `timeIntervalSince1970`-style
    /// payloads. See review #14.
    init(clampingFinite value: Double) {
        if value.isNaN || value.isInfinite {
            self = 0
            return
        }
        if value >= Double(Int64.max) {
            self = Int64.max
            return
        }
        if value <= Double(Int64.min) {
            self = Int64.min
            return
        }
        self = Int64(value)
    }
}

/// Free helper to round + safe-cast: convenient for "round to nearest Int
/// seconds / servings / percentage" use-cases. NaN/Infinity → 0.
func intRoundedClamped(_ value: Double) -> Int {
    Int(clampingFinite: value.rounded())
}
