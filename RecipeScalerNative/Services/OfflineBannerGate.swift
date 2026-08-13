//
//  OfflineBannerGate.swift
//  RecipeScalerNative
//
//  Spec 066 — debounce показа оффлайн-баннеров.
//
//  Shared-гейт с задержанным показом (по умолчанию 3с) и мгновенным скрытием.
//  Обновляется из единственного места (`AppShellView`) и инжектится через
//  `@Environment` всем status-баннерам. Сигнал — `!connectionState.isConnected`
//  (тот же, что у `AssistantSheet`); feature-gating места остаются на мгновенном
//  чтении `connectionState.isConnected`, а gate добавляет debounce, чтобы
//  status-баннеры не мелькали при разблокировке телефона.
//
//  Время в `.background` не считается: `AppShellView` вызывает
//  `update(isNotConnected: false)` при уходе в фон и заново армит на `.active`.
//  `.connecting` / `.reconnecting` НЕ снимают arm (иначе авиарежим сбрасывал
//  бы таймер на каждом backoff).
//

import Foundation

@MainActor
@Observable
final class OfflineBannerGate {
    /// Публичное UI-состояние: показывать ли status-баннеры. `false` на init.
    private(set) var isVisible = false

    /// Порог показа в наносекундах. По умолчанию 3 секунды.
    private let thresholdNs: UInt64

    /// Cancellable arm-task. Только один активный одновременно
    /// (предыдущий отменяется перед запуском нового — single-flight).
    private var armTask: Task<Void, Never>?

    /// Дедупликация повторных `update(isNotConnected: true)` без промежуточного `false`.
    private var lastSeenNotConnected = false

    init(thresholdSeconds: Double = 3) {
        self.thresholdNs = UInt64(thresholdSeconds * 1_000_000_000)
    }

    /// Обновить gate текущим `!connectionState.isConnected`.
    ///
    /// - При переходе в not-connected: запускает cancellable `Task` со `sleep(thresholdNs)`;
    ///   по завершении без cancellation ставит `isVisible = true`.
    /// - При `.connected` (или reset на background): отменяет task и мгновенно
    ///   ставит `isVisible = false`.
    /// - Игнорирует повторные `true` без промежуточного `false` (защита от дублирующего arm
    ///   на `.connecting` / `.reconnecting`).
    func update(isNotConnected: Bool) {
        if isNotConnected {
            guard !lastSeenNotConnected else { return }
            lastSeenNotConnected = true
            armTask?.cancel()
            // Capture threshold synchronously so the closure has no implicit
            // `self.` reference before the first `await` (Swift 6 strict mode).
            let sleepNs = thresholdNs
            armTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: sleepNs)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.isVisible = true
            }
        } else {
            lastSeenNotConnected = false
            armTask?.cancel()
            armTask = nil
            isVisible = false
        }
    }
}
