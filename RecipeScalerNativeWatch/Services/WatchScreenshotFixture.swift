//
//  WatchScreenshotFixture.swift
//  RecipeScalerNativeWatch
//
//  DEBUG-only store frames. Launch:
//    -ScreenshotCapture=1 -WatchScreenshot=timers|empty -AppLanguage=ru|en
//

import Foundation
import RecipeScalerCore

#if DEBUG
enum WatchScreenshotFixture {
    enum Scene: String {
        case timers
        case empty
    }

    static var isEnabled: Bool { scene != nil }

    static var scene: Scene? {
        guard boolFlag("ScreenshotCapture") else { return nil }
        let raw = stringValue("WatchScreenshot") ?? Scene.timers.rawValue
        return Scene(rawValue: raw)
    }

    /// `-AppLanguage=ru|en`. Falls back to the process language.
    static var language: String {
        if let raw = stringValue("AppLanguage")?.lowercased(), raw == "ru" || raw == "en" {
            return raw
        }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code.hasPrefix("ru") ? "ru" : "en"
    }

    static var loadState: WatchTimerService.LoadState {
        switch scene {
        case .timers:
            return .loaded(timers)
        case .empty, nil:
            return .empty
        }
    }

    /// Three running timers. Remaining stays on a minute boundary long enough
    /// for the screenshot. The shortest one is in the "soon" palette.
    private static var timers: [WatchTimer] {
        let names = language == "ru"
            ? ["Штрудель в духовке", "Сырники", "Лохикейтто"]
            : ["Strudel in the oven", "Syrniki", "Lohikeitto"]
        let specs: [(duration: Int, remaining: Int)] = [
            (3600, 2700),
            (1200, 720),
            (900, 70),
        ]
        let now = Date()
        let anchorMs = Int64(now.timeIntervalSince1970 * 1000)
        return zip(names, specs).enumerated().map { index, pair in
            let remaining = pair.1.remaining
            // Paused so the label does not tick during capture. The row has
            // no pause icon; the palette matches a running timer.
            return WatchTimer(server: ServerActiveTimer(
                timerId: "screenshot-\(index)",
                name: pair.0,
                duration: pair.1.duration,
                endTime: anchorMs + Int64(remaining) * 1000,
                isPaused: true,
                pausedDuration: nil,
                createdAt: anchorMs,
                lastUpdated: anchorMs,
                startedAt: anchorMs - Int64(pair.1.duration - remaining) * 1000,
                pausedAt: anchorMs,
                recipeId: nil
            ))
        }
    }

    private static func boolFlag(_ name: String) -> Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-\(name)=1" || arg == "-\(name)" { return true }
        }
        return false
    }

    private static func stringValue(_ name: String) -> String? {
        let prefix = "-\(name)="
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix(prefix) {
            let value = String(arg.dropFirst(prefix.count))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
#endif
