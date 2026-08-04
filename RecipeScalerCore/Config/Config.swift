//
//  Config.swift
//  RecipeScalerCore
//
//  Centralized configuration constants shared between the main app and extensions.
//

import Foundation

public enum Config {
    /// Production default. E2E UI tests override via launch env
    /// (`E2E_OVERRIDE_API_BASE` / `E2E_OVERRIDE_WS_BASE`) so SeedClient and
    /// the app share the same local backend (web Playwright: localhost:3001).
    /// Env override is honored in DEBUG only — Release always uses the
    /// production URL so a hostile `E2E_OVERRIDE_API_BASE` cannot redirect
    /// traffic. See review finding High #6.
    public static var baseURL: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["E2E_OVERRIDE_API_BASE"],
           !override.isEmpty {
            return override
        }
        #endif
        return "https://recipe-scaler.ru"
    }

    public static var wsBaseURL: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["E2E_OVERRIDE_WS_BASE"],
           !override.isEmpty {
            return override
        }
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

    /// Hosts accepted for Universal Links (spec 059). Derived from `baseURL`
    /// so DEBUG `E2E_OVERRIDE_API_BASE` exercises the UL parser against a
    /// local backend, and any domain change in one place propagates here too.
    /// Always includes the `www.` variant (and strips it if `baseURL` already
    /// has one) so both forms are accepted in production.
    public static var universalLinkHosts: Set<String> {
        guard let host = URL(string: baseURL)?.host?.lowercased(), !host.isEmpty else {
            return []
        }
        if host.hasPrefix("www.") {
            return [host, String(host.dropFirst("www.".count))]
        }
        return [host, "www.\(host)"]
    }
}
