//
//  TimerLiveActivityFormatting.swift
//  RecipeScalerNative
//

import Foundation

/// Time formatting shared by app and Live Activity extension.
enum TimerLiveActivityFormatting {
    static func formatTime(seconds: Int) -> String {
        let isNegative = seconds < 0
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let secs = absSeconds % 60
        let body: String
        if hours > 0 {
            body = String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            body = String(format: "%02d:%02d", minutes, secs)
        }
        return isNegative ? "-\(body)" : body
    }
}
