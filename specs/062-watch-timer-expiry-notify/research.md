# Phase 0 — Research: watchOS expiry notification + Settings

**Дата**: 2026-08-11
**Спека**: [spec.md](./spec.md) | **План**: [plan.md](./plan.md)

Закрывает 5 NEEDS CLARIFICATION из секции Phase 0 плана.

## R1 — Доступ watch-таргета к `Localizable.xcstrings`

**Findings** (из `project.pbxproj`):

- Файл `RecipeScalerNative/Resources/Localizable.xcstrings` имеет `fileRef = 0A5A136ADBF870BFBD1C3902`.
- Этот же fileRef включён в **три** Resources phases: main app (`FB47945F9C6342719A745D7B`), Action Extension (`14D3BD00201333243554AB3B`), Share Extension (`179F96A874E4A191DFC84958`).
- Watch target (Sources phase `A23BBE31762D4611BB03B6DA`) **не включает** ни `Localizable.xcstrings`, ни `Bundle+Language.swift`, ни `AppLog.swift` — это исключительно watch-specific файлы.

**Проверка runtime**: watch-код использует `LocalizedStringKey("watch.timer.empty.title")` (см. `EmptyStateView.swift`). `LocalizedStringKey` резолвится SwiftUI через `Bundle.main` автоматически. На watch app `Bundle.main` = `RecipeScalerNativeWatch.app`, и **внутри этого bundle нет `Localizable.xcstrings`** — пока.

**Решение**: добавить `Localizable.xcstrings` в Resources фазу watch target (новый `PBXBuildFile` entry + запись в watch Resources phase `7E50E48B98A048F4A53A6B6F` или как там она называется). Это позволяет:

- `LocalizedStringKey` резолвить watch-строки напрямую.
- `Bundle.main.localizedString(forKey:...)` возвращать `String` для `UNMutableNotificationContent.title/body`.

`Shared.xcstrings` уже шарится между extensions через main app — но **watch target не использует Shared.xcstrings** (только main + extensions). Поэтому кладём новые watch-ключи в **`Localizable.xcstrings`** (main file, добавив в Resources watch phase).

**Альтернативы**:
- Дублировать watch-ключи в `Shared.xcstrings` и добавлять watch target к Shared build phase — усложняет maintenance (два места для watch-строк).
- Создать watch-local `WatchLocalizable.xcstrings` — плодит ещё один файл.

Выбранное решение — единый `Localizable.xcstrings` (как для iOS UI, так и для watch UI).

**Почемуwatch-код до сих пор работал без явной Resources фазы для xcstrings**: проверим build через verify-скрипт — если `Text(LocalizedStringKey("watch.timer.empty.title"))` уже работает на часах, значит ключи из main app bundle подгружаются через shared app group или просто падают в fallback. Это нужно перепроверить билдом; если работает — наш план минимум затронет pbxproj (просто добавить новый ключ в xcstrings). Если не работает — добавить Resources entry.

**Action**: проверить в фазе verify-build текущего состояния, реально ли watch-app видит `watch.timer.empty.title`. Если да — новых ключей в xcstrings достаточно. Если нет — добавить `Localizable.xcstrings` в watch Resources phase (см. data-model.md).

## R2 — `UNUserNotificationCenter` на watchOS

**Findings**:

- `UNUserNotificationCenter` доступен на watchOS 6.0+ (наш deployment target — watchOS 10+ через iOS 17+ constraint).
- `requestAuthorization(options:)` поддерживает `.alert`, `.sound`, `.badge` на watchOS 9+. На watchOS 10 `.alert` включает в себя haptic + visual banner.
- Haptic при delivery: система автоматически проигрывает haptic при показе alert — отдельный `UNNotificationHapticFeedback` не нужен.
- При `.denied` permission: `requestAuthorization` возвращает `false`. Повторный запрос системой не поддерживается — пользователь должен включить в Watch → Settings → Notifications → Recipe Scaler.

**Решение**: запрашиваем `[.alert, .sound]` (без `.badge` — на часах badge не нужен). Звук в **content** явно `nil`, но в authorization запрашиваем — это разрешение покрывает и haptic delivery. При denial — Settings UI показывает тумблер, но он no-op; добавим footnote-строку «Чтобы включить, откройте Настройки часов → Уведомления».

## R3 — Foreground delivery suppression

**Findings**: на watchOS, если приложение открыто в момент срабатывания `UNCalendarNotificationTrigger`, система **не показывает** banner автоматически (поведение отличается от iOS). `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)` вызывается только если app зарегистрировано как delegate. На watchOS delegate можно установить в `WKApplicationDelegate` (watchOS 9+) или `WKExtensionDelegate`.

Наш watch app использует `@main App` (SwiftUI lifecycle), без `WKApplicationDelegate`. Установить delegate можно через `UNUserNotificationCenter.current().delegate = ...` в `RecipeScalerNativeWatchApp.init()`.

**Решение**: установить delegate в `init()` app. В `willPresent` возвращаем `[]` (без `.banner`, `.sound`, `.list`) — это **подавляет** показ и звук, foreground haptic уже отработал в `checkForExpirations`. Логируем delivery через `os_log`/`print` (AppLog недоступен — см. R5).

Если доставка пришла через push, а app в foreground — foreground haptic мог быть уже сыгран (если `firedExpirations` содержит timerId), либо ещё нет (если poll через 15с ещё не догнал). Возвращаем `[]` в обоих случаях — лучше пропустить вторую вибрацию, чем дать двойную.

## R4 — `UNCalendarNotificationTrigger` vs `UNTimeIntervalNotificationTrigger`

**Findings**:

- `UNCalendarNotificationTrigger(dateComponents:)` — абсолютное время, стабильно при изменении timezone устройства (привязывается к календарю).
- `UNTimeIntervalNotificationTrigger(timeInterval:)` — относительное, может漂нуть при изменении системных часов.

**Решение**: `UNCalendarNotificationTrigger` с `DateComponents` от `endDate`, через `Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: endDate)`. Если `endDate` уже прошёл на момент планирования — система срабатывает немедленно; наша `grace` отсечка (5 секунд от now) защищает от массового «немедленного» срабатывания при cold start.

## R5 — Логирование на часах без `AppLog`

**Findings** (pbxproj Sources phase `A23BBE31762D4611BB03B6DA`): watch target не включает `AppLog.swift`, и добавлять его не будем (он тащит зависимости на main-app типы вроде `AppContainer`).

**Решение**: для логирования на watch используем `os.Logger` напрямую:

```swift
import os
private let logger = Logger(subsystem: "ru.recipescaler.RecipeScaler.watch", category: "ExpiryScheduler")
logger.error("Failed to schedule: \(error.localizedDescription)")
```

Это консистентно с тем, как сделан NDJSON debug-session log на main app (тот же subsystem prefix). Pull-app-logs.sh забирает NDJSON из sandbox — на часах будем полагаться на Console.app + `os.Logger` для manual QA.

---

## Итог

Все 5 NEEDS CLARIFICATION закрыты. Можно переходить к Phase 1 design артефактам.
