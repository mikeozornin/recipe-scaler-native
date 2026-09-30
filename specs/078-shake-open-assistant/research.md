# Research: Shake → open assistant

**Дата**: 2026-09-30

## Decision: UIWindow.motionEnded + Notification

SwiftUI не даёт native shake. Стандартный bridge (Hacking with Swift / Catch):

1. `extension UIWindow { open override func motionEnded(...) }` при `.motionShake` постит `Notification`.
2. SwiftUI `onReceive` в `AppShellView` (один слушатель app-wide).
3. `super.motionEnded` сохраняет Shake to Undo.

Альтернатива `CMMotionManager` отклонена: батарея, пороги, сложнее debounce, нет HIG «shake gesture».

Caveat: override через Swift extension на ObjC method работает через runtime; subclass UIWindow из SceneDelegate в pure SwiftUI App тяжелее без кастомного window.

## Decision: Debounce 1.0 s

Системный shake часто шлёт один event, но на практике бывают double-fires. Gate: `DeviceShakeDetector.shouldAcceptShake(now:debounce:)` чистая функция для unit-теста. Default 1.0 s.

## Decision: Open / attach / voice wiring

Существующий путь:
- `openAssistantManually()` ставит `assistantContextRecipeId = visibleRecipeId` и `showAssistant = true`.
- Context recipe показывается как **tag** (tap to attach), не auto-attach.
- Voice стартует только по кнопке mic в `AssistantComposerChrome`.

Shake требует:
- auto-attach (не tag),
- auto-start voice,
- force new chat когда рецепта нет.

Поэтому отдельный `AssistantShakeOpenRequest` (не перегружаем `AssistantOpenRequest` с message для 072 feed).

## Decision: Preference key

`shakeToOpenAssistantEnabled` в `UserDefaults.standard`. `Bool` missing → false — идеальный default OFF без миграции.

## Decision: Settings placement

Секция `account.section.preferences` («Параметры») — язык, тема, layout коллекций, КБЖУ. Это «Interface» из запроса пользователя.

## Open questions

1. Конфликт с Shake to Undo при pref ON в text fields — приемлемо для v1?
2. Нужен ли haptic при успешном shake-open?
