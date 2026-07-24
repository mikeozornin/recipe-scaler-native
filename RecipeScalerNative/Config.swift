//
//  Config.swift
//  RecipeScalerNative
//
//

import Foundation

enum Config {
    /// Production default. E2E UI tests may override via launch env so the
    /// app and SeedClient share the same local backend (web Playwright parity:
    /// `localhost:3001`). Env override is honored in DEBUG only — Release
    /// always uses the production URL so a hostile `E2E_OVERRIDE_API_BASE`
    /// cannot redirect traffic. See review finding High #6.
    static var baseURL: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["E2E_OVERRIDE_API_BASE"],
           !override.isEmpty {
            return override
        }
        #endif
        return "https://recipe-scaler.ru"
    }

    static var wsBaseURL: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["E2E_OVERRIDE_WS_BASE"],
           !override.isEmpty {
            return override
        }
        // Derive ws(s) from http(s) base when overridden.
        if let override = ProcessInfo.processInfo.environment["E2E_OVERRIDE_API_BASE"],
           !override.isEmpty {
            if override.hasPrefix("https://") {
                return "wss://" + String(override.dropFirst("https://".count))
            }
            if override.hasPrefix("http://") {
                return "ws://" + String(override.dropFirst("http://".count))
            }
        }
        #endif
        return "wss://recipe-scaler.ru"
    }
}
