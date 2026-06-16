//
//  PushScheduleService.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

@MainActor
final class PushScheduleService {
    static let shared = PushScheduleService()

    private struct VoidData: Decodable {}

    private init() {}

    /// Schedule a server-side push for the given timer. Returns true on success.
    /// Server applies reminder logic: if duration_seconds > 1800, also sends a 2-min reminder.
    func schedule(timerId: String, name: String, durationSeconds: Int, recipeId: String?) async -> Bool {
        struct Body: Encodable {
            let timer_id: String
            let title: String
            let locale: String
            let duration_seconds: Int
            let recipe_id: String?
        }
        let body = Body(
            timer_id: timerId,
            title: name,
            locale: AppLanguagePreference.current.rawValue,
            duration_seconds: max(1, durationSeconds),
            recipe_id: recipeId
        )
        do {
            let _: APIResponse<VoidData> = try await APIClient.shared.requestJSON(
                path: "/api/push/schedule",
                method: "POST",
                body: body
            )
            return true
        } catch {
            AppLog.error(.push, "Schedule failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Cancel a previously scheduled server push.
    func cancel(timerId: String) async {
        struct Body: Encodable {
            let timer_id: String
        }
        let body = Body(timer_id: timerId)
        do {
            let _: APIResponse<VoidData> = try await APIClient.shared.requestJSON(
                path: "/api/push/cancel",
                method: "POST",
                body: body
            )
        } catch {
            AppLog.error(.push, "Cancel failed: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let openRecipe = Notification.Name("OpenRecipeNotification")
}
